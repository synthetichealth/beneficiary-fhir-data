package gov.cms.bfd.pipeline.rda.grpc.sink.direct;

import com.codahale.metrics.Gauge;
import com.codahale.metrics.Histogram;
import com.codahale.metrics.Meter;
import com.codahale.metrics.MetricRegistry;
import com.google.common.annotations.VisibleForTesting;
import com.google.protobuf.util.JsonFormat;
import gov.cms.bfd.model.rda.MessageError;
import gov.cms.bfd.model.rda.RdaApiProgress;
import gov.cms.bfd.model.rda.RdaClaimMessageMetaData;
import gov.cms.bfd.pipeline.rda.grpc.NumericGauges;
import gov.cms.bfd.pipeline.rda.grpc.ProcessingException;
import gov.cms.bfd.pipeline.rda.grpc.RdaChange;
import gov.cms.bfd.pipeline.rda.grpc.RdaSink;
import gov.cms.bfd.pipeline.rda.grpc.source.DataTransformer;
import gov.cms.bfd.pipeline.sharedutils.PipelineApplicationState;
import java.io.IOException;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.OptionalLong;
import java.util.concurrent.atomic.AtomicLong;
import javax.persistence.EntityManager;
import lombok.Getter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * RdaSink implementation that writes TClaim objects to the database in batches within the calling
 * thread. This class is abstract and derived classes implement the methods that depend on the
 * actual class of RDA API message and database entity.
 *
 * @param <TMessage> type of RDA API messages written to the database
 * @param <TClaim> type of entity objects written to the database
 */
abstract class AbstractClaimRdaSink<TMessage, TClaim>
    implements RdaSink<TMessage, RdaChange<TClaim>> {
  protected final EntityManager entityManager;
  protected final Metrics metrics;
  protected final Clock clock;
  protected final Logger logger;
  protected final RdaApiProgress.ClaimType claimType;
  protected final boolean autoUpdateLastSeq;

  /** Holds the underlying value of our sequence number gauges. */
  private static final NumericGauges GAUGES = new NumericGauges();

  /** Used to write out RDA messages to json strings */
  protected static final JsonFormat.Printer protobufObjectWriter =
      JsonFormat.printer().omittingInsignificantWhitespace();

  /**
   * Constructs an instance using the provided appState and claimType. Sequence numbers can either
   * be written in the same transaction as their associated claims (autoUpdateLastSeq=true) or not
   * auto updated (autoUpdateLastSeq=false). Generally the former is used for single-threaded
   * processing and the latter for multi-threaded processing.
   *
   * @param appState provides database and metrics configuration
   * @param claimType used to write claim type when recording sequence number updates
   * @param autoUpdateLastSeq controls whether sequence numbers are automatically written to the
   *     database
   */
  protected AbstractClaimRdaSink(
      PipelineApplicationState appState,
      RdaApiProgress.ClaimType claimType,
      boolean autoUpdateLastSeq) {
    entityManager = appState.getEntityManagerFactory().createEntityManager();
    metrics = new Metrics(getClass(), appState.getMetrics());
    clock = appState.getClock();
    logger = LoggerFactory.getLogger(getClass());
    this.claimType = claimType;
    this.autoUpdateLastSeq = autoUpdateLastSeq;
  }

  @Override
  public void close() throws Exception {
    if (entityManager != null && entityManager.isOpen()) {
      entityManager.close();
    }
  }

  /**
   * Queries the RdaApiProgress table to get the maximum sequence number for our claim type.
   *
   * @return max sequence number or empty if there is no record for this claim type
   * @throws ProcessingException if the operation fails
   */
  @Override
  public Optional<Long> readMaxExistingSequenceNumber() throws ProcessingException {
    try {
      logger.info("running query to find max sequence number");
      String query =
          String.format(
              "select p.%s from RdaApiProgress p where p.claimType='%s'",
              RdaApiProgress.Fields.lastSequenceNumber, claimType.name());
      final List<Long> sequenceNumber =
          entityManager.createQuery(query, Long.class).getResultList();
      final Optional<Long> answer =
          sequenceNumber.isEmpty() ? Optional.empty() : Optional.of(sequenceNumber.get(0));
      logger.info(
          "max sequence number result is {}", answer.map(n -> Long.toString(n)).orElse("none"));
      return answer;
    } catch (Exception ex) {
      throw new ProcessingException(ex, 0);
    }
  }

  /**
   * Writes the sequence number to the database in the calling thread.
   *
   * @param lastSequenceNumber value to write to the database
   */
  @Override
  public void updateLastSequenceNumber(long lastSequenceNumber) {
    boolean commit = false;
    entityManager.getTransaction().begin();
    try {
      updateLastSequenceNumberImpl(lastSequenceNumber);
      commit = true;
    } finally {
      if (commit) {
        entityManager.getTransaction().commit();
      } else {
        entityManager.getTransaction().rollback();
      }
    }
  }

  /**
   * Writes out the transformation error to the database for the given message and given apiVersion.
   *
   * @param apiVersion The version of the api used to get the message.
   * @param message The message that was being transformed when the error occurred.
   * @param exception The exception that was thrown while transforming the message.
   * @throws IOException If there was an issue writing to the database.
   */
  @Override
  public void writeError(
      String apiVersion, TMessage message, DataTransformer.TransformationException exception)
      throws IOException {
    entityManager.getTransaction().begin();
    entityManager.merge(createMessageError(apiVersion, message, exception.getErrors()));
    entityManager.getTransaction().commit();
  }

  /**
   * Writes the claims immediately and returns the number written.
   *
   * @param apiVersion value for the apiSource column of the claim record
   * @param messages zero or more objects to be written to the data store
   * @return number of objects successfully processed
   * @throws ProcessingException if the operation fails
   */
  @Override
  public int writeMessages(String apiVersion, List<TMessage> messages) throws ProcessingException {
    try {
      final List<RdaChange<TClaim>> claims = transformMessages(apiVersion, messages);
      return writeClaims(claims);
    } catch (DataTransformer.TransformationException e) {
      throw new ProcessingException(e, 0);
    }
  }

  /**
   * Writes the claims to the database in the calling thread.
   *
   * @param claims objects to be written
   * @return number successfully written
   * @throws ProcessingException if the operation fails
   */
  @Override
  public int writeClaims(Collection<RdaChange<TClaim>> claims) throws ProcessingException {
    final long maxSeq = maxSequenceInBatch(claims);
    try {
      metrics.calls.mark();
      updateLatencyMetric(claims);
      mergeBatch(maxSeq, claims);
      metrics.objectsMerged.mark(claims.size());
      logger.debug("writeBatch succeeded using merge: size={} maxSeq={} ", claims.size(), maxSeq);
    } catch (Exception error) {
      logger.error(
          "writeBatch failed: size={} maxSeq={} error={}",
          claims.size(),
          maxSeq,
          error.getMessage(),
          error);
      metrics.failures.mark();
      throw new ProcessingException(error, 0);
    }
    metrics.successes.mark();
    metrics.objectsWritten.mark(claims.size());
    return claims.size();
  }

  /**
   * Always returns zero since all claims are written synchronously by writeMessages.
   *
   * @return zero
   * @throws ProcessingException if the operation fails
   */
  @Override
  public int getProcessedCount() throws ProcessingException {
    return 0;
  }

  /**
   * Does nothing since there is no thread pool to close.
   *
   * @param waitTime maximum amount of time to wait for shutdown to complete
   * @throws ProcessingException if the operation fails
   */
  @Override
  public void shutdown(Duration waitTime) throws ProcessingException {}

  @VisibleForTesting
  Metrics getMetrics() {
    return metrics;
  }

  /**
   * Apply implementation specific logic to produce a populated {@link RdaClaimMessageMetaData}
   * object suitable for insertion into the database to track this update.
   *
   * @param change an incoming RdaChange object from which to extract meta data
   * @return an object ready for insertion into the database
   */
  abstract RdaClaimMessageMetaData createMetaData(RdaChange<TClaim> change);

  /**
   * Helper method to generate {@link MessageError} entities from a given claim object. This is
   * implementation specific logic for each claim type.
   *
   * @param apiVersion The version of the api the message was pulled from.
   * @param change The claim change object that was being transformed when the error occurred.
   * @param errors The transformation errors that occurred during the claim transformation.
   * @return A new {@link MessageError} entity containing the details of the transformation error
   *     and associated claim change object.
   * @throws IOException If there was an issue writing the details to the {@link MessageError}
   *     entity.
   */
  abstract MessageError createMessageError(
      String apiVersion, TMessage change, List<DataTransformer.ErrorMessage> errors)
      throws IOException;

  private void updateLastSequenceNumberImpl(long lastSequenceNumber) {
    RdaApiProgress progress =
        RdaApiProgress.builder()
            .claimType(claimType)
            .lastSequenceNumber(lastSequenceNumber)
            .lastUpdated(clock.instant())
            .build();
    entityManager.merge(progress);
    metrics.setLatestSequenceNumber(lastSequenceNumber);
    logger.debug("updated max sequence number: type={} seq={}", claimType, lastSequenceNumber);
  }

  @VisibleForTesting
  List<RdaChange<TClaim>> transformMessages(String apiVersion, Collection<TMessage> messages)
      throws ProcessingException {
    var claims = new ArrayList<RdaChange<TClaim>>();
    for (TMessage message : messages) {
      try {
        var change = transformMessage(apiVersion, message);
        metrics.transformSuccesses.mark();
        claims.add(change);
      } catch (DataTransformer.TransformationException transformationException) {
        metrics.transformFailures.mark();
        try {
          writeError(apiVersion, message, transformationException);
        } catch (IOException e) {
          transformationException.addSuppressed(e);
        }
        throw transformationException;
      }
    }
    return claims;
  }

  private void mergeBatch(long maxSeq, Iterable<RdaChange<TClaim>> changes) {
    boolean commit = false;
    try {
      entityManager.getTransaction().begin();
      for (RdaChange<TClaim> change : changes) {
        if (change.getType() != RdaChange.Type.DELETE) {
          var metaData = createMetaData(change);
          entityManager.merge(metaData);
          entityManager.merge(change.getClaim());
        } else {
          // TODO: [DCGEO-131] accept DELETE changes from RDA API
          throw new IllegalArgumentException("RDA API DELETE changes are not currently supported");
        }
      }
      if (autoUpdateLastSeq) {
        updateLastSequenceNumberImpl(maxSeq);
      }
      commit = true;
    } finally {
      if (commit) {
        entityManager.getTransaction().commit();
      } else {
        entityManager.getTransaction().rollback();
      }
      entityManager.clear();
    }
  }

  private long maxSequenceInBatch(Collection<RdaChange<TClaim>> claims) {
    OptionalLong value = claims.stream().mapToLong(RdaChange::getSequenceNumber).max();
    if (!value.isPresent()) {
      // This should never happen! But if it does, we'll shout about it rather than throw an
      // exception
      logger.warn("processed an empty batch!");
    }
    return value.orElse(0L);
  }

  /**
   * Used by sub-classes to read the highest known sequenceNumber for claims in the database.
   *
   * @param query JPAQL query string
   * @return result of the query or empty if no records matched
   * @throws ProcessingException the processing exception
   */
  protected Optional<Long> readMaxExistingSequenceNumber(String query) throws ProcessingException {
    try {
      logger.info("running query to find max sequence number");
      Long sequenceNumber = entityManager.createQuery(query, Long.class).getSingleResult();
      final Optional<Long> answer = Optional.ofNullable(sequenceNumber);
      logger.info(
          "max sequence number result is {}", answer.map(n -> Long.toString(n)).orElse("none"));
      return answer;
    } catch (Exception ex) {
      throw new ProcessingException(ex, 0);
    }
  }

  private void updateLatencyMetric(Collection<RdaChange<TClaim>> claims) {
    for (RdaChange<TClaim> claim : claims) {
      final long nowMillis = clock.millis();
      final long changeMillis = claim.getTimestamp().toEpochMilli();
      final long age = Math.max(0L, nowMillis - changeMillis);
      metrics.changeAgeMillis.update(age);
    }
  }

  /**
   * Metrics are tested in unit tests so they need to be easily accessible from tests. Also this
   * class is used to write both MCS and FISS claims so the metric names need to include a claim
   * type to distinguish them.
   */
  @Getter
  @VisibleForTesting
  static class Metrics {
    /** Number of times the sink has been called to store objects. */
    private final Meter calls;
    /** Number of calls that successfully stored the objects. */
    private final Meter successes;
    /** Number of calls that failed to store the objects. */
    private final Meter failures;
    /** Number of objects written. */
    private final Meter objectsWritten;
    /** Number of objects stored using <code>persist()</code>. */
    private final Meter objectsPersisted;
    /** Number of objects stored using <code>merge()</code> */
    private final Meter objectsMerged;
    /** Number of objects successfully transformed. */
    private final Meter transformSuccesses;
    /** Number of objects which failed to be transformed. */
    private final Meter transformFailures;
    /** Milliseconds between change timestamp and current time. */
    private final Histogram changeAgeMillis;
    /** Latest sequnce number from writing a batch. * */
    private final Gauge<?> latestSequenceNumber;
    /** The value returned by the latestSequenceNumber gauge. * */
    private final AtomicLong latestSequenceNumberValue;

    private Metrics(Class<?> klass, MetricRegistry appMetrics) {
      final String base = klass.getSimpleName();
      calls = appMetrics.meter(MetricRegistry.name(base, "calls"));
      successes = appMetrics.meter(MetricRegistry.name(base, "successes"));
      failures = appMetrics.meter(MetricRegistry.name(base, "failures"));
      objectsWritten = appMetrics.meter(MetricRegistry.name(base, "writes", "total"));
      objectsPersisted = appMetrics.meter(MetricRegistry.name(base, "writes", "persisted"));
      objectsMerged = appMetrics.meter(MetricRegistry.name(base, "writes", "merged"));
      transformSuccesses = appMetrics.meter(MetricRegistry.name(base, "transform", "successes"));
      transformFailures = appMetrics.meter(MetricRegistry.name(base, "transform", "failures"));
      changeAgeMillis =
          appMetrics.histogram(MetricRegistry.name(base, "change", "latency", "millis"));
      String latestSequenceNumberGaugeName = MetricRegistry.name(base, "lastSeq");
      latestSequenceNumber = GAUGES.getGaugeForName(appMetrics, latestSequenceNumberGaugeName);
      latestSequenceNumberValue = GAUGES.getValueForName(latestSequenceNumberGaugeName);
    }

    @VisibleForTesting
    void setLatestSequenceNumber(long value) {
      latestSequenceNumberValue.set(value);
    }
  }
}

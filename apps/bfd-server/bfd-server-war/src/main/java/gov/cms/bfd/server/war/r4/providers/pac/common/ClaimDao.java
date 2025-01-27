package gov.cms.bfd.server.war.r4.providers.pac.common;

import ca.uhn.fhir.rest.param.DateParam;
import ca.uhn.fhir.rest.param.DateRangeParam;
import ca.uhn.fhir.rest.param.ParamPrefixEnum;
import com.codahale.metrics.MetricRegistry;
import com.codahale.metrics.Timer;
import com.google.common.annotations.VisibleForTesting;
import gov.cms.bfd.model.rda.Mbi;
import gov.cms.bfd.server.war.commons.QueryUtils;
import gov.cms.bfd.server.war.r4.providers.TransformerUtilsV2;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import javax.persistence.EntityManager;
import javax.persistence.criteria.CriteriaBuilder;
import javax.persistence.criteria.CriteriaQuery;
import javax.persistence.criteria.Path;
import javax.persistence.criteria.Predicate;
import javax.persistence.criteria.Root;

/** Provides common logic for performing DB interactions */
public class ClaimDao {

  private static final String CLAIM_BY_MBI_METRIC_QUERY = "claim_by_mbi";
  private static final String CLAIM_BY_MBI_METRIC_NAME =
      MetricRegistry.name(ClaimDao.class.getSimpleName(), "query", CLAIM_BY_MBI_METRIC_QUERY);
  private static final String CLAIM_BY_ID_METRIC_QUERY = "claim_by_id";
  private static final String CLAIM_BY_ID_METRIC_NAME =
      MetricRegistry.name(ClaimDao.class.getSimpleName(), "query", CLAIM_BY_ID_METRIC_QUERY);

  private final EntityManager entityManager;
  private final MetricRegistry metricRegistry;
  private final boolean isOldMbiHashEnabled;

  public ClaimDao(
      EntityManager entityManager, MetricRegistry metricRegistry, boolean isOldMbiHashEnabled) {
    this.entityManager = entityManager;
    this.metricRegistry = metricRegistry;
    this.isOldMbiHashEnabled = isOldMbiHashEnabled;
  }

  /**
   * Gets an entity by it's ID for the given claim type.
   *
   * @param type The type of claim to retrieve.
   * @param id The id of the claim to retrieve.
   * @return An entity object of the given type provided in {@link ResourceTypeV2}
   */
  public Object getEntityById(ResourceTypeV2<?> type, String id) {
    return getEntityById(type.getEntityClass(), type.getEntityIdAttribute(), id);
  }

  /**
   * Gets an entity by it's ID for the given claim type.
   *
   * @param entityClass The type of entity to retrieve.
   * @param entityIdAttribute The name of the entity's id attribute.
   * @param id The id value of the claim to retrieve.
   * @param <T> The entity type of the claim.
   * @return The retrieved entity of the given type for the requested claim id.
   */
  @VisibleForTesting
  <T> T getEntityById(Class<T> entityClass, String entityIdAttribute, String id) {
    T claimEntity = null;

    CriteriaBuilder builder = entityManager.getCriteriaBuilder();
    CriteriaQuery<T> criteria = builder.createQuery(entityClass);
    Root<T> root = criteria.from(entityClass);

    criteria.select(root);
    criteria.where(builder.equal(root.get(entityIdAttribute), id));

    Timer.Context timerClaimQuery = metricRegistry.timer(CLAIM_BY_ID_METRIC_NAME).time();
    try {
      claimEntity = entityManager.createQuery(criteria).getSingleResult();
    } finally {
      logQueryMetric(timerClaimQuery.stop(), claimEntity == null ? 0 : 1);
    }

    return claimEntity;
  }

  /**
   * Find records by MBI (hashed or unhashed) based on a given {@link Mbi} attribute name and search
   * value with a given last updated range.
   *
   * @param entityClass The entity type to retrieve.
   * @param mbiRecordAttributeName The name of the entity's mbiRecord attribute..
   * @param mbiSearchValue The desired value of the attribute be searched on.
   * @param isMbiSearchValueHashed True iff the mbiSearchValue is a hashed MBI.
   * @param lastUpdated The range of lastUpdated values to search on.
   * @param serviceDate Date range of the desired service date to search on.
   * @param idAttributeName The name of the entity attribute denoting its ID
   * @param endDateAttributeName The name of the entity attribute denoting service end date.
   * @param <T> The entity type being retrieved.
   * @return A list of entities of type T retrieved matching the given parameters.
   */
  public <T> List<T> findAllByMbiAttribute(
      Class<T> entityClass,
      String mbiRecordAttributeName,
      String mbiSearchValue,
      boolean isMbiSearchValueHashed,
      DateRangeParam lastUpdated,
      DateRangeParam serviceDate,
      String idAttributeName,
      String endDateAttributeName) {
    List<T> claimEntities = null;

    CriteriaBuilder builder = entityManager.getCriteriaBuilder();
    CriteriaQuery<T> criteria = builder.createQuery(entityClass);
    Root<T> root = criteria.from(entityClass);

    criteria.select(root);
    criteria.where(
        builder.and(
            createMbiPredicate(
                root.get(mbiRecordAttributeName),
                mbiSearchValue,
                isMbiSearchValueHashed,
                isOldMbiHashEnabled,
                builder),
            lastUpdated == null
                ? builder.and()
                : createDateRangePredicate(root, lastUpdated, builder),
            serviceDate == null
                ? builder.and()
                : serviceDateRangePredicate(root, serviceDate, builder, endDateAttributeName)));
    // This sort will ensure predictable responses for any current/future testing needs
    criteria.orderBy(builder.asc(root.get(idAttributeName)));

    Timer.Context timerClaimQuery = metricRegistry.timer(CLAIM_BY_MBI_METRIC_NAME).time();
    try {
      claimEntities = entityManager.createQuery(criteria).getResultList();
    } finally {
      logQueryMetric(timerClaimQuery.stop(), claimEntities == null ? 0 : claimEntities.size());
    }

    return claimEntities;
  }

  /**
   * Helper method for easier mocking related to metrics.
   *
   * @param queryTime The amount of time passed executing the query.
   * @param querySize The number of entities returned by the query.
   */
  @VisibleForTesting
  void logQueryMetric(long queryTime, int querySize) {
    TransformerUtilsV2.recordQueryInMdc(CLAIM_BY_MBI_METRIC_QUERY, queryTime, querySize);
  }

  /**
   * Helper method to create the appropriate MBI predicate depending on if the current or old MBI
   * Hash should be used.
   *
   * @param root The root path of the entity to get attributes from.
   * @param mbiSearchValue The MBI value being searched for.
   * @param isMbiSearchValueHashed Indicates if the search value is a hash or raw MBI.
   * @param isOldMbiHashEnabled Indicates if the old MBI should be checked for the query.
   * @param builder The builder to use for creating predicates.
   * @return A {@link Predicate} that checks for the given mbi value.
   */
  @VisibleForTesting
  Predicate createMbiPredicate(
      Path<?> root,
      String mbiSearchValue,
      boolean isMbiSearchValueHashed,
      boolean isOldMbiHashEnabled,
      CriteriaBuilder builder) {
    final String mbiValueAttributeName = isMbiSearchValueHashed ? Mbi.Fields.hash : Mbi.Fields.mbi;
    var answer = builder.equal(root.get(mbiValueAttributeName), mbiSearchValue);
    if (isMbiSearchValueHashed && isOldMbiHashEnabled) {
      var oldHashPredicate = builder.equal(root.get(Mbi.Fields.oldHash), mbiSearchValue);
      answer = builder.or(answer, oldHashPredicate);
    }
    return answer;
  }

  /**
   * Helper method to create a date range predicat to make mocking easier.
   *
   * @param root The root path of the entity to get attributes from.
   * @param dateRange The date range to search for.
   * @param builder The builder to use for creating predicates.
   * @return A {@link Predicate} that checks for the given date range.
   */
  @VisibleForTesting
  Predicate createDateRangePredicate(
      Root<?> root, DateRangeParam dateRange, CriteriaBuilder builder) {
    return QueryUtils.createLastUpdatedPredicateInstant(builder, root, dateRange);
  }

  /**
   * Helper method to create a service date range predicate.
   *
   * @param root The root path of the entity to get attributes from.
   * @param serviceDate The service date to search for.
   * @param builder The builder to use for creating predicates.
   * @param endDateAttributeName The name of the end date attribute on the entity.
   * @return A {@link Predicate} that checks for the given service date range.
   */
  @VisibleForTesting
  Predicate serviceDateRangePredicate(
      Root<?> root,
      DateRangeParam serviceDate,
      CriteriaBuilder builder,
      String endDateAttributeName) {
    Path<LocalDate> serviceDateEndPath = root.get(endDateAttributeName);

    List<Predicate> predicates = new ArrayList<>();

    DateParam lowerBound = serviceDate.getLowerBound();

    if (lowerBound != null) {
      LocalDate from = lowerBound.getValue().toInstant().atOffset(ZoneOffset.UTC).toLocalDate();

      if (ParamPrefixEnum.GREATERTHAN.equals(lowerBound.getPrefix())) {
        predicates.add(builder.greaterThan(serviceDateEndPath, from));
      } else if (ParamPrefixEnum.GREATERTHAN_OR_EQUALS.equals(lowerBound.getPrefix())) {
        predicates.add(builder.greaterThanOrEqualTo(serviceDateEndPath, from));
      } else {
        throw new IllegalArgumentException(
            String.format("Unsupported prefix supplied %s", lowerBound.getPrefix()));
      }
    }

    DateParam upperBound = serviceDate.getUpperBound();

    if (upperBound != null) {
      LocalDate to = upperBound.getValue().toInstant().atOffset(ZoneOffset.UTC).toLocalDate();

      if (ParamPrefixEnum.LESSTHAN_OR_EQUALS.equals(upperBound.getPrefix())) {
        predicates.add(builder.lessThanOrEqualTo(serviceDateEndPath, to));
      } else if (ParamPrefixEnum.LESSTHAN.equals(upperBound.getPrefix())) {
        predicates.add(builder.lessThan(serviceDateEndPath, to));
      } else {
        throw new IllegalArgumentException(
            String.format("Unsupported prefix supplied %s", upperBound.getPrefix()));
      }
    }

    return builder.and(predicates.toArray(new Predicate[0]));
  }

  @Override
  public boolean equals(Object o) {
    if (this == o) return true;
    if (o == null || getClass() != o.getClass()) return false;
    ClaimDao claimDao = (ClaimDao) o;
    return Objects.equals(entityManager, claimDao.entityManager)
        && Objects.equals(metricRegistry, claimDao.metricRegistry);
  }

  @Override
  public int hashCode() {
    return Objects.hash(entityManager, metricRegistry);
  }
}

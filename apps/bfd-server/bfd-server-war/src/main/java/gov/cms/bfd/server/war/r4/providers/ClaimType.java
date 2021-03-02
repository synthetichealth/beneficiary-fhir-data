package gov.cms.bfd.server.war.r4.providers;

import com.codahale.metrics.MetricRegistry;
import gov.cms.bfd.model.rif.Beneficiary;
import gov.cms.bfd.model.rif.InpatientClaim;
import gov.cms.bfd.model.rif.InpatientClaim_;
import gov.cms.bfd.model.rif.OutpatientClaim;
import gov.cms.bfd.model.rif.OutpatientClaim_;
import gov.cms.bfd.model.rif.PartDEvent;
import gov.cms.bfd.model.rif.PartDEvent_;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Optional;
import java.util.function.BiFunction;
import java.util.function.Function;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.Id;
import javax.persistence.metamodel.PluralAttribute;
import javax.persistence.metamodel.SingularAttribute;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;

/**
 * Enumerates the various Beneficiary FHIR Data Server (BFD) claim types that are supported by
 * {@link R4ExplanationOfBenefitResourceProvider}.
 */
public enum ClaimType {
  PDE(
      PartDEvent.class,
      PartDEvent_.eventId,
      PartDEvent_.beneficiaryId,
      (entity) -> ((PartDEvent) entity).getPrescriptionFillDate(),
      PartDEventTransformerV2::transform),

  INPATIENT(
      InpatientClaim.class,
      InpatientClaim_.claimId,
      InpatientClaim_.beneficiaryId,
      (entity) -> ((InpatientClaim) entity).getDateThrough(),
      InpatientClaimTransformerV2::transform,
      InpatientClaim_.lines),

  OUTPATIENT(
      OutpatientClaim.class,
      OutpatientClaim_.claimId,
      OutpatientClaim_.beneficiaryId,
      (entity) -> ((OutpatientClaim) entity).getDateThrough(),
      OutpatientClaimTransformerV2::transform,
      OutpatientClaim_.lines);

  private final Class<?> entityClass;
  private final SingularAttribute<?, ?> entityIdAttribute;
  private final SingularAttribute<?, String> entityBeneficiaryIdAttribute;
  private final Function<Object, LocalDate> serviceEndAttributeFunction;
  private final BiFunction<MetricRegistry, Object, ExplanationOfBenefit> transformer;
  private final Collection<PluralAttribute<?, ?, ?>> entityLazyAttributes;

  /**
   * Enum constant constructor.
   *
   * @param entityClass the value to use for {@link #getEntityClass()}
   * @param entityIdAtt ibute the value to u e for {@link #getEntityIdAttribute()}
   * @param entityBeneficiaryIdA tribute the value to use for {@link
   *     #getEntityBeneficiaryIdAttribute()}
   * @param transformer the value to use for {@link #getTransformer()}
   * @param entityLazyAttributes the value to use for {@link #getEntityLazyAttributes()}
   */
  private ClaimType(
      Class<?> entityClass,
      SingularAttribute<?, ?> entityIdAttribute,
      SingularAttribute<?, String> entityBeneficiaryIdAttribute,
      Function<Object, LocalDate> serviceEndAttributeFunction,
      BiFunction<MetricRegistry, Object, ExplanationOfBenefit> transformer,
      PluralAttribute<?, ?, ?>... entityLazyAttributes) {
    this.entityClass = entityClass;
    this.entityIdAttribute = entityIdAttribute;
    this.entityBeneficiaryIdAttribute = entityBeneficiaryIdAttribute;
    this.serviceEndAttributeFunction = serviceEndAttributeFunction;
    this.transformer = transformer;
    this.entityLazyAttributes =
        entityLazyAttributes != null
            ? Collections.unmodifiableCollection(Arrays.asList(entityLazyAttributes))
            : Collections.emptyList();
  }

  /**
   * @return the JPA {@link Entity} {@link Class} used to store instances of this {@link ClaimType}
   *     in the database
   */
  public Class<?> getEntityClass() {
    return entityClass;
  }

  /** @return the JPA {@link Entity} field used as the entity's {@link Id} */
  public SingularAttribute<?, ?> getEntityIdAttribute() {
    return entityIdAttribute;
  }

  /**
   * @return the JPA {@link Entity} field that is a (foreign keyed) reference to {@link
   *     Beneficiary#getBeneficiaryId()}
   */
  public SingularAttribute<?, String> getEntityBeneficiaryIdAttribute() {
    return entityBeneficiaryIdAttribute;
  }

  /**
   * @return the {@link Function} to use to transform the JPA {@link Entity} instances into FHIR
   * @return the {@link Function} to use to retrieve the {@link LocalDate} to use for service date
   *     filter
   */
  public Function<Object, LocalDate> getServiceEndAttributeFunction() {
    return serviceEndAttributeFunction;
  }

  /**
   * @return the {@link BiFunction} to use to transform the JPA {@link Entity} instances into FHIR
   *     {@link ExplanationOfBenefit} instances
   */
  public BiFunction<MetricRegistry, Object, ExplanationOfBenefit> getTransformer() {
    return transformer;
  }

  /**
   * @return the {@link PluralAttribute}s in the JPA {@link Entity} that are {@link FetchType#LAZY}
   */
  public Collection<PluralAttribute<?, ?, ?>> getEntityLazyAttributes() {
    return entityLazyAttributes;
  }

  /**
   * @param claimTypeText the lower-cased {@link ClaimType#name()} value to parse back into a {@link
   *     ClaimType}
   * @return the {@link ClaimType} represented by the specified {@link String}
   */
  public static Optional<ClaimType> parse(String claimTypeText) {
    for (ClaimType claimType : ClaimType.values())
      if (claimType.name().toLowerCase().equals(claimTypeText)) return Optional.of(claimType);
    return Optional.empty();
  }
}

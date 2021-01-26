package gov.cms.bfd.server.war.r4.providers;

import com.codahale.metrics.MetricRegistry;
import gov.cms.bfd.model.codebook.data.CcwCodebookVariable;
import gov.cms.bfd.model.rif.Beneficiary;
import gov.cms.bfd.model.rif.samples.StaticRifResource;
import gov.cms.bfd.server.war.common.BeneficiaryTestUtil;
import gov.cms.bfd.server.war.commons.Sex;
import gov.cms.bfd.server.war.commons.TransformerConstants;
import java.util.Arrays;
import org.hl7.fhir.r4.model.Enumerations.AdministrativeGender;
import org.hl7.fhir.r4.model.Identifier;
import org.hl7.fhir.r4.model.Patient;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;

public class BeneficiaryTransformerV2Test {
  private Beneficiary beneficiary;

  @Before
  public void setup() {
    beneficiary = BeneficiaryTestUtil.loadSampleABeneficiary();
  }

  /**
   * Verifies {@link BeneficiaryTransformerV2#transform(Beneficiary)} works as expected when run
   * against the {@link StaticRifResource#SAMPLE_A_BENES} {@link Beneficiary}.
   */
  @Test
  public void transformSampleARecord() {
    Patient patient =
        BeneficiaryTransformerV2.transform(
            new MetricRegistry(), beneficiary, Arrays.asList("false"));

    assertMatches(beneficiary, patient);
    Assert.assertEquals("Number of identifiers should be 3", 3, patient.getIdentifier().size());

    // Verify identifiers and values match.
    assertValuesInPatientIdentifiers(
        patient,
        TransformerUtilsV2.calculateVariableReferenceUrl(CcwCodebookVariable.BENE_ID),
        "567834");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "3456789");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "9AB2WW3GR44");

    // Identifiers that were not requested
    assertValuesNotInPatientIdentifiers(patient, TransformerConstants.CODING_BBAPI_BENE_MBI_HASH);
    assertValuesNotInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_HASH_OLD);
    assertValuesNotInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED);
  }

  @Test
  public void transformSampleARecordWithMBIHash() {
    Patient patient =
        BeneficiaryTransformerV2.transform(
            new MetricRegistry(), beneficiary, Arrays.asList("mbi-hash"));

    assertMatches(beneficiary, patient);
    Assert.assertEquals("Number of identifiers should be 4", 4, patient.getIdentifier().size());

    // Verify identifiers and values match.
    assertValuesInPatientIdentifiers(
        patient,
        TransformerUtilsV2.calculateVariableReferenceUrl(CcwCodebookVariable.BENE_ID),
        "567834");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_MBI_HASH, "someMBIhash");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "3456789");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "9AB2WW3GR44");

    // Identifiers that were not requested
    assertValuesNotInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_HASH_OLD);
    assertValuesNotInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED);
  }

  /**
   * Verifies that {@link BeneficiaryTransformerV2#transform(Beneficiary)} works as expected when
   * run against the {@link StaticRifResource#SAMPLE_A_BENES} {@link Beneficiary}, with {@link
   * IncludeIdentifiersValues} = ["hicn","mbi"].
   */
  @Test
  public void transformSampleARecordWithIdentifiers() {
    Patient patient =
        BeneficiaryTransformerV2.transform(
            new MetricRegistry(), beneficiary, Arrays.asList("hicn", "mbi"));
    assertMatches(beneficiary, patient);

    Assert.assertEquals("Number of identifiers should be 7", 7, patient.getIdentifier().size());

    // Verify patient identifiers and values match.
    assertValuesInPatientIdentifiers(
        patient,
        TransformerUtilsV2.calculateVariableReferenceUrl(CcwCodebookVariable.BENE_ID),
        "567834");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_HASH, "someHICNhash");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066U");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "3456789");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066T");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066Z");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "9AB2WW3GR44");

    // Identifiers that were not requested
    assertValuesNotInPatientIdentifiers(patient, TransformerConstants.CODING_BBAPI_BENE_MBI_HASH);
  }

  /**
   * Verifies that {@link BeneficiaryTransformerV2#transform(Beneficiary)} works as expected when
   * run against the {@link StaticRifResource#SAMPLE_A_BENES} {@link Beneficiary}, with {@link
   * IncludeIdentifiersValues} = ["true"].
   */
  @Test
  public void transformSampleARecordWithIdentifiersTrue() {
    Patient patient =
        BeneficiaryTransformerV2.transform(
            new MetricRegistry(), beneficiary, Arrays.asList("true"));
    assertMatches(beneficiary, patient);

    Assert.assertEquals("Number of identifiers should be 8", 8, patient.getIdentifier().size());

    // Verify patient identifiers and values match.
    assertValuesInPatientIdentifiers(
        patient,
        TransformerUtilsV2.calculateVariableReferenceUrl(CcwCodebookVariable.BENE_ID),
        "567834");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_MBI_HASH, "someMBIhash");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_HASH, "someHICNhash");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066U");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "3456789");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066T");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066Z");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "9AB2WW3GR44");
  }

  /**
   * {@link BeneficiaryTransformerV2#transform(Beneficiary)} works as expected when run against the
   * {@link StaticRifResource#SAMPLE_A_BENES} {@link Beneficiary}, with {@link
   * IncludeIdentifiersValues} = ["hicn"].
   */
  @Test
  public void transformSampleARecordWithIdentifiersHicn() {
    Patient patient =
        BeneficiaryTransformerV2.transform(
            new MetricRegistry(), beneficiary, Arrays.asList("hicn"));

    assertMatches(beneficiary, patient);

    Assert.assertEquals("Number of identifiers should be 7", 7, patient.getIdentifier().size());

    // Verify patient identifiers and values match.
    assertValuesInPatientIdentifiers(
        patient,
        TransformerUtilsV2.calculateVariableReferenceUrl(CcwCodebookVariable.BENE_ID),
        "567834");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "3456789");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_MEDICARE_BENEFICIARY_ID_UNHASHED, "9AB2WW3GR44");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_HASH, "someHICNhash");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066U");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066T");
    assertValuesInPatientIdentifiers(
        patient, TransformerConstants.CODING_BBAPI_BENE_HICN_UNHASHED, "543217066Z");

    // Identifiers that were not requested
    assertValuesNotInPatientIdentifiers(patient, TransformerConstants.CODING_BBAPI_BENE_MBI_HASH);
  }

  // Utility functions

  static void assertMatches(Beneficiary beneficiary, Patient patient) {
    // TODO: TransformerTestUtils
    Assert.assertEquals(beneficiary.getBeneficiaryId(), patient.getIdElement().getIdPart());
    Assert.assertEquals(1, patient.getAddress().size());
    Assert.assertEquals(beneficiary.getStateCode(), patient.getAddress().get(0).getState());
    Assert.assertEquals(beneficiary.getCountyCode(), patient.getAddress().get(0).getDistrict());
    Assert.assertEquals(beneficiary.getPostalCode(), patient.getAddress().get(0).getPostalCode());

    // Sex
    if (beneficiary.getSex() == Sex.MALE.getCode()) {
      Assert.assertEquals(
          AdministrativeGender.MALE.toString(), patient.getGender().toString().trim());
    } else if (beneficiary.getSex() == Sex.FEMALE.getCode()) {
      Assert.assertEquals(
          AdministrativeGender.FEMALE.toString(), patient.getGender().toString().trim());
    }

    // Name
    Assert.assertEquals(
        beneficiary.getNameGiven(), patient.getName().get(0).getGiven().get(0).toString());
    if (beneficiary.getNameMiddleInitial().isPresent())
      Assert.assertEquals(
          beneficiary.getNameMiddleInitial().get().toString(),
          patient.getName().get(0).getGiven().get(1).toString());
    Assert.assertEquals(beneficiary.getNameSurname(), patient.getName().get(0).getFamily());
  }

  /**
   * Verifies that the {@link Patient} identifiers contain expected values.
   *
   * @param Patient {@link Patient} containing identifiers
   * @param identifierSystem value to be matched
   * @param identifierValue value to be matched
   */
  private static void assertValuesInPatientIdentifiers(
      Patient patient, String identifierSystem, String identifierValue) {

    boolean identifierFound = false;

    for (Identifier temp : patient.getIdentifier()) {
      if (identifierSystem.equals(temp.getSystem()) && identifierValue.equals(temp.getValue())) {
        identifierFound = true;
        break;
      }
    }

    Assert.assertEquals(
        "Identifier "
            + identifierSystem
            + " value = "
            + identifierValue
            + " does not match an expected value.",
        identifierFound,
        true);
  }

  /**
   * Verifies that the {@link Patient} identifiers do not contain values.
   *
   * @param Patient {@link Patient} containing identifiers
   * @param identifierSystem value to be matched
   * @param identifierValue value to be matched
   */
  private static void assertValuesNotInPatientIdentifiers(
      Patient patient, String identifierSystem) {

    boolean identifierFound = false;
    String identifierValue = null;

    for (Identifier temp : patient.getIdentifier()) {
      if (identifierSystem.equals(temp.getSystem())) {
        identifierFound = true;
        identifierValue = temp.getValue();
        break;
      }
    }

    Assert.assertEquals(
        "Identifier "
            + identifierSystem
            + " value = "
            + identifierValue
            + " should not be present.",
        identifierFound,
        false);
  }
}

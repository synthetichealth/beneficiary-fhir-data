package gov.cms.bfd.server.war.r4.providers;

import ca.uhn.fhir.rest.client.api.IGenericClient;
import gov.cms.bfd.model.rif.Beneficiary;
import gov.cms.bfd.model.rif.samples.StaticRifResourceGroup;
import gov.cms.bfd.server.war.ServerTestUtils;
import java.util.Arrays;
import java.util.List;
import org.hl7.fhir.r4.model.Patient;
import org.junit.Assert;
import org.junit.Test;

public class R4PatientResourceProviderIT {
  /**
   * Verifies that {@link
   * gov.cms.bfd.server.war.r4.providers.R4PatientResourceProvider#read(org.hl7.fhir.r4.model;.IdType)}
   * works as expected for a {@link Patient} that does exist in the DB.
   */
  @Test
  public void readExistingPatient() {
    List<Object> loadedRecords =
        ServerTestUtils.loadData(Arrays.asList(StaticRifResourceGroup.SAMPLE_A.getResources()));
    IGenericClient fhirClient = ServerTestUtils.createFhirClient();

    Beneficiary beneficiary =
        loadedRecords.stream()
            .filter(r -> r instanceof Beneficiary)
            .map(r -> (Beneficiary) r)
            .findFirst()
            .get();

    Patient patient =
        fhirClient.read().resource(Patient.class).withId(beneficiary.getBeneficiaryId()).execute();

    Assert.assertNotNull(patient);
    BeneficiaryTransformerV2Test.assertMatches(beneficiary, patient);
  }
}

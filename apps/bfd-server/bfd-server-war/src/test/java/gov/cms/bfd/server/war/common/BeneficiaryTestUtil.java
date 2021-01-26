package gov.cms.bfd.server.war.common;

import gov.cms.bfd.model.rif.Beneficiary;
import gov.cms.bfd.model.rif.BeneficiaryHistory;
import gov.cms.bfd.model.rif.MedicareBeneficiaryIdHistory;
import gov.cms.bfd.model.rif.samples.StaticRifResourceGroup;
import gov.cms.bfd.server.war.ServerTestUtils;
import java.util.*;
import java.util.stream.Collectors;

public class BeneficiaryTestUtil {
  /**
   * @return the {@link StaticRifResourceGroup#SAMPLE_A} {@link Beneficiary} record, with the {@link
   *     Beneficiary#getBeneficiaryHistories()} and {@link
   *     Beneficiary#getMedicareBeneficiaryIdHistories()} fields populated.
   */
  public static Beneficiary loadSampleABeneficiary() {
    List<Object> parsedRecords =
        ServerTestUtils.parseData(Arrays.asList(StaticRifResourceGroup.SAMPLE_A.getResources()));

    // Pull out the base Beneficiary record and fix its HICN and MBI-HASH fields.
    Beneficiary beneficiary =
        parsedRecords.stream()
            .filter(r -> r instanceof Beneficiary)
            .map(r -> (Beneficiary) r)
            .findFirst()
            .get();

    beneficiary.setHicnUnhashed(Optional.of(beneficiary.getHicn()));
    beneficiary.setHicn("someHICNhash");
    beneficiary.setMbiHash(Optional.of("someMBIhash"));

    // Add the HICN history records to the Beneficiary, and fix their HICN fields.
    Set<BeneficiaryHistory> beneficiaryHistories =
        parsedRecords.stream()
            .filter(r -> r instanceof BeneficiaryHistory)
            .map(r -> (BeneficiaryHistory) r)
            .filter(r -> beneficiary.getBeneficiaryId().equals(r.getBeneficiaryId()))
            .collect(Collectors.toSet());

    beneficiary.getBeneficiaryHistories().addAll(beneficiaryHistories);

    for (BeneficiaryHistory beneficiaryHistory : beneficiary.getBeneficiaryHistories()) {
      beneficiaryHistory.setHicnUnhashed(Optional.of(beneficiaryHistory.getHicn()));
      beneficiaryHistory.setHicn("someHICNhash");
    }

    // Add the MBI history records to the Beneficiary.
    Set<MedicareBeneficiaryIdHistory> beneficiaryMbis =
        parsedRecords.stream()
            .filter(r -> r instanceof MedicareBeneficiaryIdHistory)
            .map(r -> (MedicareBeneficiaryIdHistory) r)
            .filter(r -> beneficiary.getBeneficiaryId().equals(r.getBeneficiaryId().orElse(null)))
            .collect(Collectors.toSet());

    beneficiary.getMedicareBeneficiaryIdHistories().addAll(beneficiaryMbis);

    return beneficiary;
  }
}

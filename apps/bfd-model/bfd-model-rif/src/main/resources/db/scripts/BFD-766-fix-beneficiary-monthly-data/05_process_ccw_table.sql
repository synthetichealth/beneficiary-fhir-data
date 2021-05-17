--
-- Create PROCEDURE update_bene_monthly
--
CREATE OR REPLACE PROCEDURE update_bene_monthly(
    bene_id                     "BeneficiaryMonthly"."parentBeneficiary"%TYPE,
    yr_month                    "BeneficiaryMonthly"."yearMonth"%TYPE,
    fips_cnty_code              "BeneficiaryMonthly"."fipsStateCntyCode"%TYPE,
    medi_status_code            "BeneficiaryMonthly"."medicareStatusCode"%TYPE,
    buy_in_ind                  "BeneficiaryMonthly"."entitlementBuyInInd"%TYPE,
    hmo_ind                     "BeneficiaryMonthly"."hmoIndicatorInd"%TYPE,
    partc_contract_number_id    "BeneficiaryMonthly"."partCContractNumberId"%TYPE,
    partc_pbp_number_id         "BeneficiaryMonthly"."partCPbpNumberId"%TYPE,
    partc_plan_type             "BeneficiaryMonthly"."partCPlanTypeCode"%TYPE,
    partd_contract_number_id    "BeneficiaryMonthly"."partDContractNumberId"%TYPE,
    partd_pbp_number_id         "BeneficiaryMonthly"."partDPbpNumberId"%TYPE,
    partd_segment_num           "BeneficiaryMonthly"."partDSegmentNumberId"%TYPE,
    partd_retiree_mnthly        "BeneficiaryMonthly"."partDRetireeDrugSubsidyInd"%TYPE,
    partd_low_inc_cost_share    "BeneficiaryMonthly"."partDLowIncomeCostShareGroupCode"%TYPE,
    dual_elig_code              "BeneficiaryMonthly"."medicaidDualEligibilityCode"%TYPE
)
AS
$$
BEGIN
    IF     fips_cnty_code            IS NOT NULL
        OR medi_status_code          IS NOT NULL
        OR buy_in_ind                IS NOT NULL
        OR hmo_ind                   IS NOT NULL
        OR partc_contract_number_id  IS NOT NULL
        OR partc_pbp_number_id       IS NOT NULL
        OR partc_plan_type           IS NOT NULL
        OR partd_contract_number_id  IS NOT NULL
        OR partd_pbp_number_id       IS NOT NULL
        OR partd_segment_num         IS NOT NULL
        OR partd_retiree_mnthly      IS NOT NULL
        OR partd_low_inc_cost_share  IS NOT NULL
        OR dual_elig_code            IS NOT NULL
    THEN
        UPDATE public."BeneficiaryMonthly"
        SET
            "fipsStateCntyCode"                 = fips_cnty_code,
            "medicareStatusCode"                = medi_status_code,
            "entitlementBuyInInd"               = buy_in_ind,
            "hmoIndicatorInd"                   = hmo_ind,
            "partCContractNumberId"             = partc_contract_number_id,
            "partCPbpNumberId"                  = partc_pbp_number_id,
            "partCPlanTypeCode"                 = partc_plan_type,
            "partDContractNumberId"             = partd_contract_number_id,
            "partDPbpNumberId"                  = partd_pbp_number_id,
            "partDSegmentNumberId"              = partd_segment_num,
            "partDRetireeDrugSubsidyInd"        = partd_retiree_mnthly,
            "partDLowIncomeCostShareGroupCode"  = partd_low_inc_cost_share,
            "medicaidDualEligibilityCode"       = dual_elig_code
        WHERE
            "parentBeneficiary" = bene_id
        AND
            "yearMonth" = yr_month;

        IF NOT FOUND THEN
            INSERT INTO public."BeneficiaryMonthly"
            VALUES(
                bene_id,
                yr_month,
                fips_cnty_code,
                medi_status_code,
                buy_in_ind,
                hmo_ind,
                partc_contract_number_id,
                partc_pbp_number_id,
                partc_plan_type,
                partd_contract_number_id,
                partd_pbp_number_id,
                partd_segment_num,
                partd_retiree_mnthly,
                dual_elig_code,
                partd_low_inc_cost_share
            );
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;

--
-- Create PROCEDURE load_from_ccw which is a cursor-based
-- processor of data in the CCW_LOAD_TEMP table
--
CREATE OR REPLACE PROCEDURE load_from_ccw()
AS
$$
DECLARE
  msg           VARCHAR(255);
  rcd_cnt       INTEGER := 0;
  expected_cnt  INTEGER := 0;
  loop_cnt      INTEGER := 0;
  MAX_INNER     INTEGER := 10000;    -- max # of rows to process in <<INNER>> LOOP
  cur_yr        VARCHAR;
  rcd           CCW_LOAD_TEMP%ROWTYPE;
  currYear      VARCHAR(4) := '9999';
  okToCont      BOOLEAN := true;
  inError       BOOLEAN := false;
  Jan1          DATE;
  Feb1          DATE;
  Mar1          DATE;
  Apr1          DATE;
  May1          DATE;
  Jun1          DATE;
  Jul1          DATE;
  Aug1          DATE;
  Sep1          DATE;
  Oct1          DATE;
  Nov1          DATE;
  Dec1          DATE;
  
  curs          CURSOR FOR
                      SELECT * FROM public.CCW_LOAD_TEMP;
BEGIN
    RAISE INFO 'Starting processing of table: CCW_LOAD_TEMP at % ...', NOW();
    
    SELECT INTO expected_cnt count(*) from CCW_LOAD_TEMP;
    RAISE INFO 'Expected record count in table: CCW_LOAD_TEMP: %', expected_cnt;

    open curs;
  
    <<outer>>
    LOOP
        loop_cnt := 0;
        
        BEGIN
            <<inner>>
            LOOP
                FETCH curs INTO rcd;
                
                IF NOT FOUND
                THEN
                    RAISE INFO 'No more records to process....';
                    okToCont := false;
                    EXIT inner;
                END IF;

                -- try for some efficiency w/ monthly dates since the cursor
                -- will have exec'd a simple fetch (no index used) and we know
                -- the structure of the table is all 2019 rcds then 2020 rcds;
                -- so (if lucky) we may just calc dates twice!
                IF rcd.RFRNC_YR <> currYear
                THEN
                    RAISE INFO 'Updating monthly date cache for: %', rcd.RFRNC_YR;
                    Jan1 := TO_DATE(rcd.RFRNC_YR || '-01-01', 'YYYY-MM-DD');
                    Feb1 := TO_DATE(rcd.RFRNC_YR || '-02-01', 'YYYY-MM-DD');
                    Mar1 := TO_DATE(rcd.RFRNC_YR || '-03-01', 'YYYY-MM-DD');
                    Apr1 := TO_DATE(rcd.RFRNC_YR || '-04-01', 'YYYY-MM-DD');
                    May1 := TO_DATE(rcd.RFRNC_YR || '-05-01', 'YYYY-MM-DD');
                    Jun1 := TO_DATE(rcd.RFRNC_YR || '-06-01', 'YYYY-MM-DD');
                    Jul1 := TO_DATE(rcd.RFRNC_YR || '-07-01', 'YYYY-MM-DD');
                    Aug1 := TO_DATE(rcd.RFRNC_YR || '-08-01', 'YYYY-MM-DD');
                    Sep1 := TO_DATE(rcd.RFRNC_YR || '-09-01', 'YYYY-MM-DD');
                    Oct1 := TO_DATE(rcd.RFRNC_YR || '-10-01', 'YYYY-MM-DD');
                    Nov1 := TO_DATE(rcd.RFRNC_YR || '-11-01', 'YYYY-MM-DD');
                    Dec1 := TO_DATE(rcd.RFRNC_YR || '-12-01', 'YYYY-MM-DD');
                    currYear := rcd.RFRNC_YR;
                END IF;
        
                -- Jan
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Jan1,
                    rcd.FIPS_STATE_CNTY_JAN_CD,
                    rcd.MDCR_STUS_JAN_CD,
                    rcd.MDCR_ENTLMT_BUYIN_1_IND,
                    rcd.HMO_1_IND,
                    rcd.PTC_CNTRCT_JAN_ID,
                    rcd.PTC_PBP_JAN_ID,
                    rcd.PTC_PLAN_TYPE_JAN_CD,
                    rcd.PTD_CNTRCT_JAN_ID,
                    rcd.PTD_PBP_JAN_ID,
                    rcd.PTD_SGMT_JAN_ID,
                    rcd.RDS_JAN_IND,
                    rcd.CST_SHR_GRP_JAN_CD,
                    rcd.META_DUAL_ELGBL_STUS_JAN_CD);
            
                -- Feb
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Feb1,
                    rcd.FIPS_STATE_CNTY_FEB_CD,
                    rcd.MDCR_STUS_FEB_CD,
                    rcd.MDCR_ENTLMT_BUYIN_2_IND,
                    rcd.HMO_2_IND,
                    rcd.PTC_CNTRCT_FEB_ID,
                    rcd.PTC_PBP_FEB_ID,
                    rcd.PTC_PLAN_TYPE_FEB_CD,
                    rcd.PTD_CNTRCT_FEB_ID,
                    rcd.PTD_PBP_FEB_ID,
                    rcd.PTD_SGMT_FEB_ID,
                    rcd.RDS_FEB_IND,
                    rcd.CST_SHR_GRP_FEB_CD,
                    rcd.META_DUAL_ELGBL_STUS_FEB_CD);
            
                -- Mar
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Mar1,
                    rcd.FIPS_STATE_CNTY_MAR_CD,
                    rcd.MDCR_STUS_MAR_CD,
                    rcd.MDCR_ENTLMT_BUYIN_3_IND,
                    rcd.HMO_3_IND,
                    rcd.PTC_CNTRCT_MAR_ID,
                    rcd.PTC_PBP_MAR_ID,
                    rcd.PTC_PLAN_TYPE_MAR_CD,
                    rcd.PTD_CNTRCT_MAR_ID,
                    rcd.PTD_PBP_MAR_ID,
                    rcd.PTD_SGMT_MAR_ID,
                    rcd.RDS_MAR_IND,
                    rcd.CST_SHR_GRP_MAR_CD,
                    rcd.META_DUAL_ELGBL_STUS_MAR_CD);
            
                -- Apr
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Apr1,
                    rcd.FIPS_STATE_CNTY_APR_CD,
                    rcd.MDCR_STUS_APR_CD,
                    rcd.MDCR_ENTLMT_BUYIN_4_IND,
                    rcd.HMO_4_IND,
                    rcd.PTC_CNTRCT_APR_ID,
                    rcd.PTC_PBP_APR_ID,
                    rcd.PTC_PLAN_TYPE_APR_CD,
                    rcd.PTD_CNTRCT_APR_ID,
                    rcd.PTD_PBP_APR_ID,
                    rcd.PTD_SGMT_APR_ID,
                    rcd.RDS_APR_IND,
                    rcd.CST_SHR_GRP_APR_CD,
                    rcd.META_DUAL_ELGBL_STUS_APR_CD);
            
                -- May
                call update_bene_monthly(
                    rcd.BENE_ID,
                    May1,
                    rcd.FIPS_STATE_CNTY_MAY_CD,
                    rcd.MDCR_STUS_MAY_CD,
                    rcd.MDCR_ENTLMT_BUYIN_5_IND,
                    rcd.HMO_5_IND,
                    rcd.PTC_CNTRCT_MAY_ID,
                    rcd.PTC_PBP_MAY_ID,
                    rcd.PTC_PLAN_TYPE_MAY_CD,
                    rcd.PTD_CNTRCT_MAY_ID,
                    rcd.PTD_PBP_MAY_ID,
                    rcd.PTD_SGMT_MAY_ID,
                    rcd.RDS_MAY_IND,
                    rcd.CST_SHR_GRP_MAY_CD,
                    rcd.META_DUAL_ELGBL_STUS_MAY_CD);
            
                -- Jun
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Jun1,
                    rcd.FIPS_STATE_CNTY_JUN_CD,
                    rcd.MDCR_STUS_JUN_CD,
                    rcd.MDCR_ENTLMT_BUYIN_6_IND,
                    rcd.HMO_6_IND,
                    rcd.PTC_CNTRCT_JUN_ID,
                    rcd.PTC_PBP_JUN_ID,
                    rcd.PTC_PLAN_TYPE_JUN_CD,
                    rcd.PTD_CNTRCT_JUN_ID,
                    rcd.PTD_PBP_JUN_ID,
                    rcd.PTD_SGMT_JUN_ID,
                    rcd.RDS_JUN_IND,
                    rcd.CST_SHR_GRP_JUN_CD,
                    rcd.META_DUAL_ELGBL_STUS_JUN_CD);
            
                -- Jul
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Jul1,
                    rcd.FIPS_STATE_CNTY_JUL_CD,
                    rcd.MDCR_STUS_JUL_CD,
                    rcd.MDCR_ENTLMT_BUYIN_7_IND,
                    rcd.HMO_7_IND,
                    rcd.PTC_CNTRCT_JUL_ID,
                    rcd.PTC_PBP_JUL_ID,
                    rcd.PTC_PLAN_TYPE_JUL_CD,
                    rcd.PTD_CNTRCT_JUL_ID,
                    rcd.PTD_PBP_JUL_ID,
                    rcd.PTD_SGMT_JUL_ID,
                    rcd.RDS_JUL_IND,
                    rcd.CST_SHR_GRP_JUL_CD,
                    rcd.META_DUAL_ELGBL_STUS_JUL_CD);
            
                -- Aug
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Aug1,
                    rcd.FIPS_STATE_CNTY_AUG_CD,
                    rcd.MDCR_STUS_AUG_CD,
                    rcd.MDCR_ENTLMT_BUYIN_8_IND,
                    rcd.HMO_8_IND,
                    rcd.PTC_CNTRCT_AUG_ID,
                    rcd.PTC_PBP_AUG_ID,
                    rcd.PTC_PLAN_TYPE_AUG_CD,
                    rcd.PTD_CNTRCT_AUG_ID,
                    rcd.PTD_PBP_AUG_ID,
                    rcd.PTD_SGMT_AUG_ID,
                    rcd.RDS_AUG_IND,
                    rcd.CST_SHR_GRP_AUG_CD,
                    rcd.META_DUAL_ELGBL_STUS_AUG_CD);
            
                -- Sept
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Sep1,
                    rcd.FIPS_STATE_CNTY_SEPT_CD,
                    rcd.MDCR_STUS_SEPT_CD,
                    rcd.MDCR_ENTLMT_BUYIN_9_IND,
                    rcd.HMO_9_IND,
                    rcd.PTC_CNTRCT_SEPT_ID,
                    rcd.PTC_PBP_SEPT_ID,
                    rcd.PTC_PLAN_TYPE_SEPT_CD,
                    rcd.PTD_CNTRCT_SEPT_ID,
                    rcd.PTD_PBP_SEPT_ID,
                    rcd.PTD_SGMT_SEPT_ID,
                    rcd.RDS_SEPT_IND,
                    rcd.CST_SHR_GRP_SEPT_CD,
                    rcd.META_DUAL_ELGBL_STUS_SEPT_CD);
            
                -- Oct
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Oct1,
                    rcd.FIPS_STATE_CNTY_OCT_CD,
                    rcd.MDCR_STUS_OCT_CD,
                    rcd.MDCR_ENTLMT_BUYIN_10_IND,
                    rcd.HMO_10_IND,
                    rcd.PTC_CNTRCT_OCT_ID,
                    rcd.PTC_PBP_OCT_ID,
                    rcd.PTC_PLAN_TYPE_OCT_CD,
                    rcd.PTD_CNTRCT_OCT_ID,
                    rcd.PTD_PBP_OCT_ID,
                    rcd.PTD_SGMT_OCT_ID,
                    rcd.RDS_OCT_IND,
                    rcd.CST_SHR_GRP_OCT_CD,
                    rcd.META_DUAL_ELGBL_STUS_OCT_CD);
            
                -- Nov
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Nov1,
                    rcd.FIPS_STATE_CNTY_NOV_CD,
                    rcd.MDCR_STUS_NOV_CD,
                    rcd.MDCR_ENTLMT_BUYIN_11_IND,
                    rcd.HMO_11_IND,
                    rcd.PTC_CNTRCT_NOV_ID,
                    rcd.PTC_PBP_NOV_ID,
                    rcd.PTC_PLAN_TYPE_NOV_CD,
                    rcd.PTD_CNTRCT_NOV_ID,
                    rcd.PTD_PBP_NOV_ID,
                    rcd.PTD_SGMT_NOV_ID,
                    rcd.RDS_NOV_IND,
                    rcd.CST_SHR_GRP_NOV_CD,
                    rcd.META_DUAL_ELGBL_STUS_NOV_CD);
            
                -- Dec
                call update_bene_monthly(
                    rcd.BENE_ID,
                    Dec1,
                    rcd.FIPS_STATE_CNTY_DEC_CD,
                    rcd.MDCR_STUS_DEC_CD,
                    rcd.MDCR_ENTLMT_BUYIN_12_IND,
                    rcd.HMO_12_IND,
                    rcd.PTC_CNTRCT_DEC_ID,
                    rcd.PTC_PBP_DEC_ID,
                    rcd.PTC_PLAN_TYPE_DEC_CD,
                    rcd.PTD_CNTRCT_DEC_ID,
                    rcd.PTD_PBP_DEC_ID,
                    rcd.PTD_SGMT_DEC_ID,
                    rcd.RDS_DEC_IND,
                    rcd.CST_SHR_GRP_DEC_CD,
                    rcd.META_DUAL_ELGBL_STUS_DEC_CD);
            
                rcd_cnt  := rcd_cnt + 1;
                loop_cnt := loop_cnt + 1;
        
                if loop_cnt = MAX_INNER
                THEN
                    EXIT inner;
                END IF;
                
            END LOOP;   -- end <<inner>>

            RAISE INFO 'implied COMMIT...Transaction ID: %', TXID_CURRENT();
        
            IF rcd_cnt % 20000 = 0
            THEN
                RAISE INFO 'Record Count: % ...%', rcd_cnt, NOW();
            END IF;
        
        EXCEPTION WHEN others THEN
            okToCont := false;
            inError  := true;
            RAISE EXCEPTION 'Error: % : %', SQLERRM::text, SQLSTATE::text;
        END;  
        
        IF NOT okToCont
        THEN
            RAISE INFO 'exiting <<outer>> loop!!!';
            EXIT outer;
        END IF;

    END LOOP;    -- end <<outer>>

    CLOSE curs;
    RAISE INFO 'implied COMMIT...Transaction ID: %', TXID_CURRENT();
    RAISE INFO 'Record Total: % ...DONE at %', rcd_cnt, NOW();
    
EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'Error: % : %', SQLERRM::text, SQLSTATE::text;
    -- implicit ROOLBACK via BEGIN sub-transaction block
END;

$$ LANGUAGE plpgsql;

--
-- Call our cursor-based processor of data in the CCW_LOAD_TEMP table
--
call load_from_ccw();
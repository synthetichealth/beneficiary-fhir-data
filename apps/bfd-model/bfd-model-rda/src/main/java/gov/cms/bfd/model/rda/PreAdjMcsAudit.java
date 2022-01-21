package gov.cms.bfd.model.rda;

import java.io.Serializable;
import java.time.Instant;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.IdClass;
import javax.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import lombok.experimental.FieldNameConstants;

/** JPA class for the McsAudits table */
@Entity
@Getter
@Setter
@Builder
@AllArgsConstructor
@NoArgsConstructor
@EqualsAndHashCode(onlyExplicitlyIncluded = true)
@FieldNameConstants
@IdClass(PreAdjMcsAudit.PK.class)
@Table(name = "`McsAudits`", schema = "`pre_adj`")
public class PreAdjMcsAudit {
  @Id
  @Column(name = "`idrClmHdIcn`", length = 15, nullable = false)
  @EqualsAndHashCode.Include
  private String idrClmHdIcn;

  @Id
  @Column(name = "`priority`", nullable = false)
  @EqualsAndHashCode.Include
  private short priority;

  @Column(name = "`lastUpdated`")
  private Instant lastUpdated;

  @Column(name = "`idrJAuditNum`")
  private Integer idrJAuditNum;

  @Column(name = "`idrJAuditInd`", length = 1)
  private String idrJAuditInd;

  @Column(name = "`idrJAuditDisp`", length = 1)
  private String idrJAuditDisp;

  /** PK class for the McsAudits table */
  @Data
  @NoArgsConstructor
  @AllArgsConstructor
  public static class PK implements Serializable {
    private String idrClmHdIcn;

    private short priority;
  }
}
package gov.cms.bfd.server.war.stu3.providers;

import ca.uhn.fhir.rest.api.Constants;
import ca.uhn.fhir.rest.server.exceptions.InvalidRequestException;
import gov.cms.bfd.model.rif.RifRecordBase;
import java.net.URI;
import java.util.List;
import java.util.Optional;
import org.hl7.fhir.dstu3.model.Bundle;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.util.MultiValueMap;
import org.springframework.web.util.UriComponents;
import org.springframework.web.util.UriComponentsBuilder;

/*
 * PageCursorBuilder encapsulates the arguments related to paging for the
 * {@link ExplanationOfBenefit} requests. The format of a cursor is:
 *   <claimType>_<claimId> where
 *      claimType is a {@link ClaimType} and
 *      claimId is a {@link String}
 */
public class EOBLinkBuilder {
  public static final String PARAM_CURSOR = "cursor";
  public static final String PARAM_LIMIT = "limit";
  public static final String CURSOR_SEPARATOR = "_";

  private static final Logger LOGGER = LoggerFactory.getLogger(EOBLinkBuilder.class);

  private final URI url;
  private final boolean isPagingRequested;
  private final int count;
  private final ClaimType claimType;
  private final String claimId;

  public EOBLinkBuilder(String urlString) {
    url = URI.create(urlString);
    MultiValueMap<String, String> params =
        UriComponentsBuilder.fromUriString(urlString).build().getQueryParams();
    isPagingRequested = parseIsPagingRequested(params);
    count = parseCountParameter(params);
    claimType = parseClaimTypeParameter(params);
    claimId = parseClaimIdParameter(params);
  }

  private boolean parseIsPagingRequested(MultiValueMap<String, String> params) {
    return params.containsKey(PARAM_LIMIT);
  }

  private int parseCountParameter(MultiValueMap<String, String> params) {
    if (params.containsKey(PARAM_LIMIT)) {
      String countString = params.getFirst(PARAM_LIMIT);
      try {
        int count = Integer.parseInt(countString);
        if (count <= 0) {
          throw new InvalidRequestException("Must have a positive count parameter: " + countString);
        }
        return count;
      } catch (NumberFormatException ex) {
        throw new InvalidRequestException("Invalid count parameter: " + countString);
      }
    } else {
      return Integer.MAX_VALUE;
    }
  }

  private ClaimType parseClaimTypeParameter(MultiValueMap<String, String> params) {
    if (params.containsKey(PARAM_CURSOR)) {
      String claimTypeText = params.getFirst(PARAM_CURSOR).split(CURSOR_SEPARATOR)[0];
      return ClaimType.parse(claimTypeText)
          .orElseThrow(
              () -> new InvalidRequestException("Invalid cursor claim type: " + claimTypeText));
    } else {
      return null;
    }
  }

  private String parseClaimIdParameter(MultiValueMap<String, String> params) {
    if (params.containsKey(PARAM_CURSOR)) {
      String claimIdText = params.getFirst(PARAM_CURSOR).split(CURSOR_SEPARATOR)[1];
      if (claimIdText.length() == 0) {
        throw new InvalidRequestException("Missing beneficiary id in cursor");
      }
      return claimIdText;
    } else {
      return null;
    }
  }

  public boolean isPagingRequested() {
    return isPagingRequested;
  }

  public int getPageSize() {
    return count;
  }

  public Optional<ClaimType> getClaimType() {
    return Optional.ofNullable(claimType);
  }

  public Optional<String> getClaimId() {
    return Optional.ofNullable(claimId);
  }

  public String buildNextCursor(ClaimType claimType, List<RifRecordBase> claims) {
    return claimType.name().toLowerCase() + CURSOR_SEPARATOR + getLastClaimId(claimType, claims);
  }

  private String getLastClaimId(ClaimType claimType, List<RifRecordBase> claims) {
    return claims.get(claims.size() - 1).getId();
  }

  public void addLinksToBundle(Bundle toBundle, String nextCursor) {
    toBundle.addLink(
        new Bundle.BundleLinkComponent()
            .setRelation(Constants.LINK_FIRST)
            .setUrl(buildFirstLink()));

    if (nextCursor != null) {
      toBundle.addLink(
          new Bundle.BundleLinkComponent()
              .setRelation(Constants.LINK_NEXT)
              .setUrl(buildLink(nextCursor)));
    }
  }

  private String buildLink(String cursor) {
    UriComponents components = UriComponentsBuilder.fromUri(url).build();
    return UriComponentsBuilder.newInstance()
        .scheme(components.getScheme())
        .host(components.getHost())
        .port(components.getPort())
        .path(components.getPath())
        .queryParams(components.getQueryParams())
        .replaceQueryParam(PARAM_CURSOR, cursor)
        .build()
        .toUriString();
  }

  private String buildFirstLink() {
    UriComponents components = UriComponentsBuilder.fromUri(url).build();
    return UriComponentsBuilder.newInstance()
        .scheme(components.getScheme())
        .host(components.getHost())
        .port(components.getPort())
        .path(components.getPath())
        .queryParams(components.getQueryParams())
        .replaceQueryParam(PARAM_CURSOR)
        .build()
        .toUriString();
  }
}

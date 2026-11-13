import '../../network/domain/network_models.dart';

enum GuardService { chatgpt, claude }

enum RegionVerdict {
  supported,
  unsupported,
  unknown,
  regionalReview,
  expiredRules,
}

/// A dated IP-country check, not a statement of account eligibility or an OS permit.
class RegionPolicy {
  static final verifiedAt = DateTime.utc(2026, 11, 13);
  static final expiresAt = DateTime.utc(2026, 12, 13);
  static const sources = {
    GuardService.chatgpt: 'https://help.openai.com/en/articles/7947663-chatgpt-supported-countries',
    GuardService.claude: 'https://www.anthropic.com/legal/supported-regions',
  };

  // ISO 3166-1 alpha-2, transcribed from the official lists on verifiedAt.
  static final chatgpt = _codes('''
    AL DZ AF AX AD AO AG AR AM AW AU AT AZ BS BH BD BB BE BZ BM BJ BT BO BA BW BR BN BG BF BI
    CV KH CM CA KY CF TD CL CO KM CG CD CR CI HR CY CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET
    FO FJ FI FR GF PF TF GA GM GE DE GH GR GD GL GT GP GN GW GY HT VA HN HU IS IN ID IQ IE
    IL IT JM JP JO KZ KE KI KW KG LA LV LB LS LR LY LI LT LU MG MW MY MV ML MT MH MQ MR MU
    YT MX FM MD MC MN ME MA MZ MM NA NR NP NL NC NZ NI NE NG MK NO OM PK PW PS PA PG PY PE
    PH PL PT QA RE RO RW BL SH KN LC MF PM VC WS SM ST SA SN RS SC SL SG SK SI SB SO ZA KR
    SS ES LK SR SE CH SD SJ TW TJ TZ TH TL TG TO TT TN TR TM TV UG UA AE GB US UY UZ VU VN
    WF YE ZM ZW
  ''');
  static final claude = _codes('''
    AL DZ AD AO AG AR AM AU AT AZ BS BH BD BB BE BZ BJ BT BO BA BW BR BN BG BF BI CV KH CM CA
    CF TD CL CO KM CG CD CR CI HR CY CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET FJ FI FR GA GM GE
    DE GH GR GD GT GN GW GY HT HN HU IS IN ID IQ IE IL IT JM JP JO KZ KE KI KW KG LA LV LB
    LS LR LY LI LT LU MG MW MY MV ML MT MH MR MU MX FM MD MC MN ME MA MZ NA NR NP NL NZ NI
    NE NG MK NO OM PK PW PS PA PG PY PE PH PL PT QA RO RW KN LC VC WS SM ST SA SN RS SC SL
    SG SK SI SO SB ZA KR SS ES LK SD SR SE CH TW TJ TZ TH TL TG TO TT TN TR TM TV UG UA AE
    GB US UY UZ VU VA VN ZM ZW
  ''');

  // Anthropic explicitly includes territories/dependencies of supported countries.
  // Deliberate finite mapping: unknown or disputed territories never inherit access.
  static const territoryParent = {
    'AX': 'FI',
    'FO': 'DK',
    'GL': 'DK',
    'GF': 'FR',
    'GP': 'FR',
    'MQ': 'FR',
    'RE': 'FR',
    'YT': 'FR',
    'PM': 'FR',
    'MF': 'FR',
    'BL': 'FR',
    'NC': 'FR',
    'PF': 'FR',
    'WF': 'FR',
    'TF': 'FR',
    'AW': 'NL',
    'CW': 'NL',
    'SX': 'NL',
    'BQ': 'NL',
    'PR': 'US',
    'GU': 'US',
    'VI': 'US',
    'AS': 'US',
    'MP': 'US',
    'UM': 'US',
    'BM': 'GB',
    'KY': 'GB',
    'AI': 'GB',
    'FK': 'GB',
    'GI': 'GB',
    'GG': 'GB',
    'IM': 'GB',
    'JE': 'GB',
    'MS': 'GB',
    'PN': 'GB',
    'SH': 'GB',
    'TC': 'GB',
    'VG': 'GB',
    'GS': 'GB',
    'CC': 'AU',
    'CX': 'AU',
    'HM': 'AU',
    'NF': 'AU',
    'CK': 'NZ',
    'NU': 'NZ',
    'TK': 'NZ',
    'BV': 'NO',
    'SJ': 'NO',
  };

  static Set<String> _codes(String value) =>
      Set.unmodifiable(value.trim().split(RegExp(r'\s+')));

  static RegionVerdict evaluate(
    GuardService service,
    String? countryCode,
    DateTime now,
  ) {
    if (now.isBefore(verifiedAt) || !now.isBefore(expiresAt)) {
      return RegionVerdict.expiredRules;
    }
    if (countryCode == null ||
        !RegExp(r'^[A-Z]{2}$').hasMatch(countryCode) ||
        {'XX', 'ZZ'}.contains(countryCode)) {
      return RegionVerdict.unknown;
    }
    // The sources specify subnational exceptions. Country-only geolocation cannot
    // prove their absence; do not silently allow all of UA or guess region aliases.
    if (countryCode == 'UA') return RegionVerdict.regionalReview;
    final supported = service == GuardService.chatgpt ? chatgpt : claude;
    final normalized = service == GuardService.claude
        ? territoryParent[countryCode] ?? countryCode
        : countryCode;
    return supported.contains(normalized)
        ? RegionVerdict.supported
        : RegionVerdict.unsupported;
  }
}

enum AdmissionBlocker {
  unverifiedIp,
  expiredCheck,
  unsupportedCountry,
  unknownCountry,
  regionalReview,
  expiredRules,
  unverifiedRoute,
  missingFilter,
}

class AdmissionAssessment {
  const AdmissionAssessment(this.country, this.reasons);
  final RegionVerdict country;
  final List<AdmissionBlocker> reasons;
  // This UI-side assessment can never authorize traffic. Only the future
  // authenticated OS service can install a route-bound, revocable permit.
  bool get mayAuthorizeTraffic => false;

  static AdmissionAssessment assess(
    GuardService service,
    FamilyObservation? observation,
    DateTime now,
  ) {
    final verdict = RegionPolicy.evaluate(
      service,
      observation?.geo?.countryCode,
      now,
    );
    final reasons = <AdmissionBlocker>[];
    if (observation?.ip == null ||
        observation?.geo == null ||
        observation?.error != null) {
      reasons.add(AdmissionBlocker.unverifiedIp);
    } else if (!observation!.isFresh(now)) {
      reasons.add(AdmissionBlocker.expiredCheck);
    }
    switch (verdict) {
      case RegionVerdict.unsupported:
        reasons.add(AdmissionBlocker.unsupportedCountry);
      case RegionVerdict.unknown:
        reasons.add(AdmissionBlocker.unknownCountry);
      case RegionVerdict.regionalReview:
        reasons.add(AdmissionBlocker.regionalReview);
      case RegionVerdict.expiredRules:
        reasons.add(AdmissionBlocker.expiredRules);
      case RegionVerdict.supported:
        break;
    }
    reasons.add(AdmissionBlocker.unverifiedRoute);
    reasons.add(AdmissionBlocker.missingFilter);
    return AdmissionAssessment(verdict, List.unmodifiable(reasons));
  }
}

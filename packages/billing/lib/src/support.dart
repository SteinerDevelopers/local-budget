/// Supporter goodwill surface — spec §5 item 5, §7.
library;

/// Region gate for external link-outs. U.S. link-outs are the permitted
/// status-quo (feasibility §3); every other or unknown region hides the
/// affordance in release builds. Broadening this (EU/DMA) is a spec edit
/// first — deliberately not preemptive.
abstract final class SupportPolicy {
  static const _allow = {'US'};

  static bool visible(String? countryCode, {bool debug = false}) =>
      countryCode != null ? _allow.contains(countryCode) : debug;
}

/// Outbound links that grant nothing in-app (store-rule compliance).
abstract final class SupportLinks {
  /// TODO(store): final handle lands with E8 store content (open question 3).
  static const bmc = 'https://buymeacoffee.com/localbudget';
}

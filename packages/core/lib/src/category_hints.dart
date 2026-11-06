import 'receipt.dart';

/// E12 §2: deterministic merchant-text → built-in-category suggestions for
/// the import preview. Pure function over strings — no database, no context:
/// the suggestion is a *name* from [the app's seed vocabulary] and the app
/// resolves it to an id only when that category actually exists.
///
/// Confidence discipline (truthfulness bar): a well-known brand token reads
/// `high`; a generic vocabulary word only reads `medium`, and the preview
/// marks medium suggestions with a visible "?" so an inferred category never
/// masquerades as a certainty. Text matching none of the lists returns null —
/// silence beats a wrong preselect.
class CategoryHints {
  const CategoryHints._();

  /// Seed category names this helper can suggest (expense side).
  static const List<String> suggested = [
    'Food',
    'Transport',
    'Utilities',
    'Fun',
    'Health',
  ];

  static final List<(String, RegExp, FieldConfidence)> _rules = _compile();

  static List<(String, RegExp, FieldConfidence)> _compile() {
    RegExp re(String p) => RegExp(p, caseSensitive: false);
    final rules = <(String, RegExp, FieldConfidence)>[];
    void brands(String cat, String pattern) =>
        rules.add((cat, re(pattern), FieldConfidence.high));
    void generic(String cat, String pattern) =>
        rules.add((cat, re(pattern), FieldConfidence.medium));

    brands(
      'Food',
      r'\bSTARBUCKS\b|\bMCDONALD|\bSUBWAY\b|\bCHIPOTLE\b|\bDOMINO'
      r'|\bPIZZA HUT\b|\bWHOLE FOODS\b|\bTRADER JOE|\bSAFEWAY\b|\bKROGER\b'
      r'|\bALDI\b|\bWEGMANS\b|\bPUBlix\b|\bCAFE\b|\bCOFFEE\b|\bGRILL\b',
    );
    generic(
      'Food',
      r'\bGROCER|\bMARKET\b|\bFOOD\b|\bRESTAURANT\b|\bDINER\b|\bDELI\b',
    );
    brands(
      'Transport',
      r'\bUBER\b|\bLYFT\b|\bSHELL\b|\bCHEVRON\b|\bEXXON\b|\bSUNOCO\b'
      r'|\bMARATHON\b|\bAIRLINES?\b|\bAMTRAK\b|\bGREYHOUND\b',
    );
    generic(
      'Transport',
      r'\bFUEL\b|\bGAS\b|\bPARKING\b|\bTRANSIT\b|\bTOLL\b|\bMETRO\b',
    );
    brands(
      'Utilities',
      r'\bPG&E\b|\bCOMCAST\b|\bXFINITY\b|\bCHARTER\b|\bSPECTRUM\b'
      r'|\bVERIZON\b|\bT[- ]?MOBILE\b|\bAT\s*&\s*T\b|\bDUKE ENERGY\b'
      r'|\bCONED\b|\bCON ED\b|\bNATIONAL GRID\b',
    );
    generic(
      'Utilities',
      r'\bELECTRIC\b|\bPOWER\b|\bWATER\b|\bENERGY\b|\bUTILITY\b'
      r'|\bINTERNET\b|\bWIRELESS\b|\bTELECOM\b',
    );
    brands(
      'Fun',
      r'\bNETFLIX\b|\bSPOTIFY\b|\bDISNEY\+?\b|\bHULU\b|\bPARAMOUNT\+\b'
      r'|\bPEACOCK\b|\bAPPLE TV\b|\bPRIME VIDEO\b|\bYOUTUBE PREMIUM\b'
      r'|\bXBOX\b|\bPLAYSTATION\b|\bSTEAM\b|\bCINEMARK\b|\bAMC THEATERS\b',
    );
    generic('Fun', r'\bMOVIE\b|\bCINEMA\b|\bTHEATER\b|\bARCADE\b');
    brands(
      'Health',
      r'\bCVS\b|\bWALGREEN|\bRITE AID\b|\bPHARMACY\b|\bKAISER\b|\bCIGNA\b'
      r'|\bAETNA\b|\bUNITEDHEALTH\b|BLUE (?:CROSS|SHIELD)|\bDENTAL\b'
      r'|\bOPTOMETRY\b|\bCOPAY\b',
    );
    generic(
      'Health',
      r'\bMEDICAL\b|\bCLINIC\b|\bHOSPITAL\b|\bDOCTOR\b|\bPHARMA\b'
      r'|\bEYE CARE\b|\bLAB\b',
    );
    return rules;
  }

  /// The suggestion for [text] — a seed category name and its confidence.
  /// High beats medium regardless of rule order; the first high found wins,
  /// and the first medium found (in Food→Health order) is the fallback.
  static (String name, FieldConfidence confidence)? suggest(String text) {
    if (text.trim().isEmpty) return null;
    (String, FieldConfidence)? medium;
    for (final (cat, pattern, confidence) in _rules) {
      if (!pattern.hasMatch(text)) continue;
      if (confidence == FieldConfidence.high) {
        return (cat, FieldConfidence.high);
      }
      medium ??= (cat, confidence);
    }
    return medium;
  }
}

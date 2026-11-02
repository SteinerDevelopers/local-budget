/// E3 budget engine (docs/design/e3-budget-engine.md §3).
///
/// Pure Dart (testing tier 1): integer minor-unit arithmetic, injected
/// `now`, no Flutter, no I/O, no clocks. Repositories map drift rows into
/// these plain inputs and render the statuses back into widgets.
library;

export 'src/engine.dart';
export 'src/materialize.dart';
export 'src/period.dart';
export 'src/reports.dart';
export 'src/rules.dart';

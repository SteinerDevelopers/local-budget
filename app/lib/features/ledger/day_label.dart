// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

/// Day-group heading text (design §2.1). Pure and locale-independent on
/// purpose for E1 — `Today`/`Yesterday`, else `Wed 29 Oct`. i18n of these
/// strings is deferred (decision 1: English UI first).
abstract final class DayLabel {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String of(DateTime day, {DateTime? today}) {
    final t = today ?? DateTime.now();
    final d0 = _dateOnly(day);
    final t0 = _dateOnly(t);
    final diff = t0.difference(d0).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_weekdays[d0.weekday - 1]} ${d0.day} ${_months[d0.month - 1]}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

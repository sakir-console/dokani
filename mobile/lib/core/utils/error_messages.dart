import '../../l10n/app_localizations.dart';
import '../network/api_exception.dart';

/// Turns any failure into one sentence the user can act on.
String describeError(Object error, AppLocalizations l10n) {
  if (error is! ApiException) return l10n.errUnknown;

  switch (error.kind) {
    case ApiErrorKind.network:
      return l10n.errNoInternet;
    case ApiErrorKind.timeout:
      return l10n.errTimeout;
    case ApiErrorKind.unauthenticated:
      return l10n.errSessionExpired;
    case ApiErrorKind.server:
      // The server already answers in the app's language (Accept-Language).
      // For validation failures, the first field message is the useful one.
      final firstField = error.fieldErrors.values.firstOrNull?.firstOrNull;
      return firstField ?? error.message ?? l10n.errUnknown;
    case ApiErrorKind.unknown:
      return l10n.errUnknown;
  }
}

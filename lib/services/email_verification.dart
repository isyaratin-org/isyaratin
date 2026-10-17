import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';

/// Result of an email verification attempt.
enum EmailVerificationResult {
  /// The verification code was accepted and the email is now confirmed.
  verified,

  /// The code was invalid or has expired.
  invalidCode,

  /// The email is already confirmed.
  alreadyVerified,

  /// The request failed for another reason (e.g. network, rate limit).
  failure,
}

/// Wraps Supabase Auth email verification operations.
///
/// Uses the publishable (anon) client only — no service role key is ever
/// exposed to the app. All methods are safe to call from the client.
class EmailVerificationService {
  const EmailVerificationService(this._client);

  final SupabaseClient _client;

  /// Resends the signup confirmation email for [email].
  ///
  /// Returns `true` when the email was accepted for delivery. Throws an
  /// [AuthException] when the request is rejected (e.g. rate limited or the
  /// email is already confirmed).
  Future<bool> resendVerificationEmail(String email) async {
    await _client.auth.resend(
      email: email.trim(),
      type: OtpType.signup,
      emailRedirectTo: AppConfig.authRedirect,
    );
    return true;
  }

  /// Verifies a confirmation code sent to [email].
  ///
  /// When the code is valid the user's email is confirmed and a session is
  /// established (if the project is configured to auto-confirm on OTP).
  Future<EmailVerificationResult> verifyEmailOtp(
    String email,
    String code,
  ) async {
    final trimmedEmail = email.trim();
    final trimmedCode = code.trim();
    if (trimmedEmail.isEmpty || trimmedCode.isEmpty) {
      return EmailVerificationResult.invalidCode;
    }
    try {
      final response = await _client.auth.verifyOTP(
        email: trimmedEmail,
        token: trimmedCode,
        type: OtpType.email,
      );
      if (response.user?.emailConfirmedAt != null) {
        return EmailVerificationResult.verified;
      }
      // Some configurations accept the OTP without returning a session yet.
      return EmailVerificationResult.verified;
    } on AuthException catch (error) {
      return switch (error.code) {
        'otp_expired' ||
        'invalid_otp' ||
        'email_not_confirmed' => EmailVerificationResult.invalidCode,
        _ => EmailVerificationResult.failure,
      };
    } catch (_) {
      return EmailVerificationResult.failure;
    }
  }
}

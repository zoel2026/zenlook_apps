import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../services/theme_service.dart';
import '../utils/supabase_guard.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 1;
  String _verifiedUserId = '';
  String _securityCode = '';
  bool _loading = false;

  final _usernameController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey1 = GlobalKey<FormState>();
  final _formKey2 = GlobalKey<FormState>();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String _tooManyMessage() =>
      '${context.l.t('too_many')} ${context.l.t('wrong_retry_15m')}';

  // Step 1: Verifikasi username + PIN sekaligus via RPC
  Future<void> _verifyUsernameAndCode() async {
    if (!_formKey1.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final supabase = maybeClient();
      if (supabase == null) throw Exception('Server tidak tersedia');

      final username = _usernameController.text.trim();
      final code = _codeController.text.trim();

      final userId = await supabase
          .rpc(
            'verify_security_code',
            params: {'p_username': username, 'p_code': code},
          )
          .then((v) => v?.toString());

      if (userId == null || userId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l.t('forgot_code_wrong'))),
        );
        return;
      }

      _verifiedUserId = userId;
      _securityCode = code;
      if (!mounted) return;
      setState(() => _step = 2);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('too_many_requests') ||
              e.toString().contains('Terlalu banyak')
          ? _tooManyMessage()
          : context.l.t('verify_failed');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Step 2: Reset password baru via RPC (bypass RLS + admin update)
  Future<void> _resetPassword() async {
    if (!_formKey2.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final supabase = maybeClient();
      if (supabase == null) throw Exception('Server tidak tersedia');

      final newPassword = _newPasswordController.text;

      await supabase.rpc(
        'reset_password_with_code',
        params: {
          'p_user_id': _verifiedUserId,
          'p_new_password': newPassword,
          'p_security_code': _securityCode,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('forgot_reset_success'))),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('too_many_requests') ||
              e.toString().contains('Terlalu banyak')
          ? _tooManyMessage()
          : context.l.t('reset_failed');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l.t('forgot_title')),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _step == 1 ? _buildStepVerify() : _buildStepNewPassword(),
          ),
        ),
      ),
    );
  }

  Widget _buildStepVerify() {
    return Form(
      key: _formKey1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.lock_reset,
            size: 80,
            color: context.textPrimary.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 16),
          Text(
            context.l.t('forgot_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l.t('verify_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textFaded(0.6),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _usernameController,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              labelText: context.l.t('username'),
              prefixIcon: const Icon(Icons.alternate_email),
            ),
            validator: (v) {
              final u = v?.trim() ?? '';
              if (u.isEmpty) return context.l.t('no_username');
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 24,
              letterSpacing: 12,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: context.l.t('security_code'),
              counterText: '',
              prefixIcon: const Icon(Icons.pin_outlined),
            ),
            validator: (v) {
              final code = v?.trim() ?? '';
              if (code.isEmpty) return context.l.t('security_code_required');
              if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
                return context.l.t('security_code_format');
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _verifyUsernameAndCode,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3D5AFE),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(context.l.t('forgot_verify')),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              context.l.t('back_to_login'),
              style: const TextStyle(color: Color(0xFF3D5AFE)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepNewPassword() {
    return Form(
      key: _formKey2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.lock_reset,
            size: 80,
            color: const Color(0xFF3D5AFE).withValues(alpha: 0.9),
          ),
          const SizedBox(height: 16),
          Text(
            context.l.t('forgot_new_pass'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l.t('new_pass_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textFaded(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _newPasswordController,
            obscureText: _obscureNew,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              labelText: context.l.t('forgot_new_pass'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            validator: (v) =>
                (v == null || v.length < 6) ? context.l.t('password_min') : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              labelText: context.l.t('forgot_confirm_pass'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return context.l.t('required');
              if (v != _newPasswordController.text) {
                return context.l.t('forgot_mismatch');
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _resetPassword,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3D5AFE),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(context.l.t('forgot_new_pass_change')),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _step = 1),
            child: Text(
              context.l.t('back'),
              style: const TextStyle(color: Color(0xFF3D5AFE)),
            ),
          ),
        ],
      ),
    );
  }
}
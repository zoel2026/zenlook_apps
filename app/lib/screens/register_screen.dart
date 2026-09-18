import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/locale_service.dart';
import '../services/theme_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _securityCodeController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _obscureCode = true;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {
          'username': _usernameController.text.trim(),
          'full_name': _fullNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'security_code': _securityCodeController.text.trim(),
        },
      );
      if (!mounted) return;

      final requiresConfirmation = res.session == null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requiresConfirmation
                ? context.l.t('register_success_email')
                : context.l.t('register_success'),
          ),
        ),
      );
      if (!requiresConfirmation) Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('SocketException')
          ? context.l.t('no_connection')
          : e.toString().contains('TimeoutException')
          ? context.l.t('timeout')
          : '${context.l.t('connect_error')}: ${e.toString()}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _securityCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l.t('register')),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l.t('create_account'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _fullNameController,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.l.t('full_name'),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? context.l.t('full_name_required')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _usernameController,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.l.t('username'),
                      prefixIcon: const Icon(Icons.alternate_email),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? context.l.t('no_username')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.l.t('email'),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      final email = v?.trim() ?? '';
                      if (email.isEmpty) return context.l.t('email_not_valid');
                      if (!RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(email)) {
                        return context.l.t('email_not_valid');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.l.t('phone_optional'),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscure,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.l.t('password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? context.l.t('password_min')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _securityCodeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: _obscureCode,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      labelText: context.l.t('security_code'),
                      counterText: '',
                      prefixIcon: const Icon(Icons.pin_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureCode
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _obscureCode = !_obscureCode),
                      ),
                    ),
                    validator: (v) {
                      final code = v?.trim() ?? '';
                      if (code.isEmpty) {
                        return context.l.t('security_code_required');
                      }
                      if (code.length != 6 ||
                          !RegExp(r'^\d{6}$').hasMatch(code)) {
                        return context.l.t('security_code_format');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l.t('security_code_hint'),
                    style: TextStyle(
                      color: context.textFaded(0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _register,
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
                        : Text(context.l.t('register')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

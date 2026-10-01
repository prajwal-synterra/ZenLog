import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/api_service.dart';
import '../../services/auth_storage.dart';
import 'day_ready_loading_screen.dart';

// ZenLog v3 §6.3 – Login screen
// "Ink & Paper" design. No OTP, no password, no sign-up.
// Username + phone number login only.

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;

  bool get _canSubmit =>
      _usernameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().length >= 8 &&
      !_isLoading;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _usernameController.addListener(() => setState(() {}));
    _phoneController.addListener(() => setState(() {}));
  }

  Future<void> _loadSavedCredentials() async {
    final username = await AuthStorage.getSavedUsername();
    if (username.isNotEmpty) {
      setState(() => _usernameController.text = username);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _phoneController.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_canSubmit) return;
    final username = _usernameController.text.trim();
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[^\d+]'), '');

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final deviceId = await AuthStorage.getOrCreateDeviceId();
    final result = await _api.login(
      username: username,
      phone: phone,
      deviceId: deviceId,
      deviceName: 'Flutter App',
    );

    if (!mounted) return;

    if (result != null) {
      final token = result['access_token'] as String?;
      if (token != null) {
        _api.setToken(token);
        await AuthStorage.saveToken(token);
        await AuthStorage.saveCredentials(
          username: username,
          phone: phone,
          displayName: (result['user'] as Map?)?['name'] as String?,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DayReadyLoadingScreen()),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Username and phone number don\'t match.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.zen;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height - 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Brand ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'ZenLog',
                      style: GoogleFonts.fraunces(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      '•',
                      style: TextStyle(
                        color: t.accent,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 48),

                // ── Headline ──
                Text(
                  'Welcome back.',
                  style: GoogleFonts.fraunces(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use the username and phone\nnumber you were set up with.',
                  style: TextStyle(
                    color: t.inkMuted,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 40),

                // ── Fields ──
                Text(
                  'Username',
                  style: TextStyle(color: t.inkMuted, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  style: TextStyle(color: t.ink, fontSize: 16),
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocus),
                  decoration: InputDecoration(
                    hintText: 'e.g. prajwal',
                    filled: true,
                    fillColor: t.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.ink, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    hintStyle: TextStyle(color: t.inkFaint),
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  'Phone number',
                  style: TextStyle(color: t.inkMuted, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+ ]'))],
                  style: TextStyle(color: t.ink, fontSize: 16),
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: '+91 98765 43210',
                    filled: true,
                    fillColor: t.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: t.ink, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    hintStyle: TextStyle(color: t.inkFaint),
                  ),
                ),

                // ── Error message ──
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: t.dangerTint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.dangerFill.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: t.dangerFill),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: t.dangerText, fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // ── Login button ──
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: AnimatedOpacity(
                    opacity: _canSubmit ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _login : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.ink,
                        foregroundColor: t.onInk,
                        disabledBackgroundColor: t.surfaceAlt,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: t.onInk),
                            )
                          : const Text(
                              'Log in',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Footer ──
                Text(
                  'No account? Ask the person who set up ZenLog for you.',
                  style: TextStyle(color: t.inkMuted, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 13, color: t.inkFaint),
                    const SizedBox(width: 5),
                    Text(
                      'Your journal stays private.',
                      style: TextStyle(color: t.inkFaint, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


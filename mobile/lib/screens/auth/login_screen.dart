import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/zen_colors.dart';
import '../../services/api_service.dart';
import '../../services/auth_storage.dart';
import '../../services/notification_service.dart';
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
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _pinFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();

  bool _obscurePin = true;
  bool _showPhoneFallback = false;
  bool _isLoading = false;
  String? _errorMessage;

  bool get _canSubmit =>
      _usernameController.text.trim().isNotEmpty &&
      (_pinController.text.trim().length >= 4 ||
          (_showPhoneFallback && _phoneController.text.trim().length >= 8)) &&
      !_isLoading;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _usernameController.addListener(() => setState(() {}));
    _pinController.addListener(() => setState(() {}));
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
    _pinController.dispose();
    _phoneController.dispose();
    _pinFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_canSubmit) return;
    final username = _usernameController.text.trim();
    final pin = _pinController.text.trim();
    final phone = _phoneController.text.trim().replaceAll(RegExp(r'[^\d+]'), '');

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final deviceId = await AuthStorage.getOrCreateDeviceId();
    final result = await _api.login(
      username: username,
      pin: pin.isNotEmpty ? pin : null,
      phone: (_showPhoneFallback && phone.isNotEmpty) ? phone : null,
      deviceId: deviceId,
      deviceName: 'Flutter App',
    );

    if (!mounted) return;

    if (result.ok && result.data != null) {
      final token = result.data!['access_token'] as String?;
      final user = result.data!['user'] as Map<String, dynamic>?;
      final hasPin = user?['has_pin'] == true;

      if (token != null) {
        _api.setToken(token);
        await AuthStorage.saveToken(token);
        await AuthStorage.saveCredentials(
          username: username,
          phone: phone,
        );
        NotificationService().syncToken();
      }
      if (!mounted) return;

      // If user logged in without PIN, prompt them to set their PIN now
      if (!hasPin) {
        await _showSetPinSheet();
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DayReadyLoadingScreen()),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.error ?? 'Username or PIN incorrect.';
      });
    }
  }

  Future<bool> _showSetPinSheet() async {
    final t = context.zen;
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure = true;
    String? sheetError;
    bool saving = false;

    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: t.line),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: t.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 22, color: t.ink),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Set Your Login PIN',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You logged in with your phone number. Set a 4 to 6-digit PIN so you can log in quickly with just your PIN next time.',
                        style: TextStyle(fontSize: 13, color: t.inkMuted, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'New PIN',
                        style: TextStyle(color: t.inkMuted, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: pinCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: obscure,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          hintText: '4 to 6 digits',
                          filled: true,
                          fillColor: t.surfaceAlt,
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 18,
                              color: t.inkMuted,
                            ),
                            onPressed: () => setSheetState(() => obscure = !obscure),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Confirm PIN',
                        style: TextStyle(color: t.inkMuted, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: confirmCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: obscure,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          hintText: 'Re-enter your PIN',
                          filled: true,
                          fillColor: t.surfaceAlt,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line)),
                        ),
                      ),
                      if (sheetError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: t.dangerTint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, size: 16, color: t.dangerFill),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  sheetError!,
                                  style: TextStyle(color: t.dangerText, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(sheetCtx, false),
                            child: Text('Skip for now', style: TextStyle(color: t.inkFaint)),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    final p = pinCtrl.text.trim();
                                    final cp = confirmCtrl.text.trim();
                                    if (p.length < 4 || p.length > 6) {
                                      setSheetState(() => sheetError = 'PIN must be 4 to 6 digits.');
                                      return;
                                    }
                                    if (p != cp) {
                                      setSheetState(() => sheetError = 'PINs do not match.');
                                      return;
                                    }

                                    setSheetState(() {
                                      saving = true;
                                      sheetError = null;
                                    });

                                    final res = await _api.setPin(pin: p);
                                    if (!sheetCtx.mounted) return;
                                    if (res.ok) {
                                      Navigator.pop(sheetCtx, true);
                                    } else {
                                      setSheetState(() {
                                        saving = false;
                                        sheetError = res.error ?? 'Failed to set PIN.';
                                      });
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: t.ink,
                              foregroundColor: t.onInk,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Set PIN & Continue'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return success == true;
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
                  'Enter your username and security PIN to continue.',
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
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_pinFocus),
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
                  'Security PIN',
                  style: TextStyle(color: t.inkMuted, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _pinController,
                  focusNode: _pinFocus,
                  keyboardType: TextInputType.number,
                  obscureText: _obscurePin,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  style: TextStyle(color: t.ink, fontSize: 16, letterSpacing: 2),
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: '••••',
                    hintStyle: TextStyle(color: t.inkFaint, letterSpacing: 2),
                    filled: true,
                    fillColor: t.surfaceAlt,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: t.inkMuted,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePin = !_obscurePin),
                    ),
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
                  ),
                ),

                const SizedBox(height: 10),

                GestureDetector(
                  onTap: () => setState(() => _showPhoneFallback = !_showPhoneFallback),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _showPhoneFallback
                          ? 'Hide phone login'
                          : "Don't have a PIN yet? Log in with phone number",
                      style: TextStyle(color: t.inkMuted, fontSize: 13, decoration: TextDecoration.underline),
                    ),
                  ),
                ),

                if (_showPhoneFallback) ...[
                  const SizedBox(height: 12),
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
                ],

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


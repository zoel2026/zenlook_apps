import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/battery_saver_service.dart';
import '../services/location_service.dart';
import '../services/locale_service.dart';
import '../services/nearby_alert.dart';
import '../services/status_service.dart';
import '../services/theme_service.dart';
import '../utils/supabase_guard.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/user_avatar.dart';
import 'login_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  SupabaseClient get supabase => Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _statusController = TextEditingController();
  String? _email;
  String? _avatarUrl;
  bool _loading = true;
  bool _saving = false;
  bool _savingStatus = false;
  String? _statusEmoji;
  StatusTtl _statusTtl = StatusTtl.defaultTtl;
  DateTime? _statusExpiresAt;
  bool _uploadingAvatar = false;
  bool _alwaysShare = false;
  ThemeMode _themeMode = ThemeMode.system;
  AppLocale _locale = AppLocale.id;
  bool _batterySaver = false;
  bool _nearbyAlerts = false;
  int _nearbyRadius = nearbyRadiusDefault;

  static const _prefAlwaysShare = 'location_always_share';

  String? get _uid => maybeClient()?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAlwaysSharePref();
    _loadTheme();
    _loadLocale();
    _batterySaver = BatterySaverService.enabled.value;
    BatterySaverService.enabled.addListener(_onBatteryChanged);
  }

  void _onBatteryChanged() {
    if (!mounted) return;
    setState(() => _batterySaver = BatterySaverService.enabled.value);
  }

  Future<void> _toggleBatterySaver(bool value) async {
    await BatterySaverService.setEnabled(value);
  }

  void _loadLocale() {
    final lc = gLocaleController;
    if (lc == null) return;
    _locale = lc.value;
    lc.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    final lc = gLocaleController;
    if (lc == null) return;
    if (!mounted) return;
    setState(() => _locale = lc.value);
  }

  Future<void> _setLocale(AppLocale locale) async {
    setState(() => _locale = locale);
    final lc = gLocaleController;
    if (lc != null) await lc.setLocale(locale);
  }

  void _loadTheme() {
    final tc = gThemeController;
    if (tc == null) return;
    _themeMode = tc.value;
    tc.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    final tc = gThemeController;
    if (tc == null) return;
    if (!mounted) return;
    setState(() => _themeMode = tc.value);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final tc = gThemeController;
    if (tc != null) await tc.setMode(mode);
  }

  Future<void> _loadAlwaysSharePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final granted = await LocationService.isAlwaysGranted();
      if (!mounted) return;
      setState(() => _alwaysShare =
          granted && (prefs.getBool(_prefAlwaysShare) ?? false));
    } catch (_) {}
  }

  Future<void> _toggleAlwaysShare(bool value) async {
    if (value) {
      final ok = await LocationService.ensureAlwaysPermission();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l.t('always_share_denied')),
            action: SnackBarAction(
              label: context.l.t('open_settings'),
              onPressed: openAppSettings,
            ),
          ),
        );
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAlwaysShare, value);
    if (!mounted) return;
    setState(() => _alwaysShare = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value
            ? context.l.t('always_share_on')
            : context.l.t('always_share_off')),
      ),
    );
  }

  Future<void> _toggleNearbyAlerts(bool value) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      _nearbyAlerts = value;
      _saving = true;
    });
    try {
      await supabase
          .from('profiles')
          .update({'nearby_alerts_enabled': value}).eq('id', uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _nearbyAlerts = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('save_profile_fail'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setNearbyRadius(double value) async {
    final uid = _uid;
    if (uid == null) return;
    final radius = clampRadius(value.round());
    setState(() => _nearbyRadius = radius);
    try {
      await supabase
          .from('profiles')
          .update({'nearby_alert_radius': radius}).eq('id', uid);
    } catch (_) {}
  }
  @override
  void dispose() {
    gThemeController?.removeListener(_onThemeChanged);
    gLocaleController?.removeListener(_onLocaleChanged);
    BatterySaverService.enabled.removeListener(_onBatteryChanged);
    _usernameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await supabase
          .from('profiles')
          .select(
              'username, full_name, avatar_url, nearby_alerts_enabled, nearby_alert_radius, '
              'status_text, status_emoji, status_expires_at')
          .eq('id', uid)
          .single();
      // Data sensitif (email/phone) tinggal di tabel terpisah own-only.
      final priv = await supabase
          .from('private_profiles')
          .select('email, phone')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _email = priv?['email'] as String?;
        _usernameController.text = (res['username'] ?? '') as String;
        _fullNameController.text = (res['full_name'] ?? '') as String;
        _phoneController.text = ((priv?['phone'] ?? '') ?? '') as String;
        _avatarUrl = (res['avatar_url'] ?? '') as String;
        _nearbyAlerts =
            (res['nearby_alerts_enabled'] ?? false) as bool;
        _nearbyRadius = clampRadius(
          (res['nearby_alert_radius'] as num?)?.toInt() ??
              nearbyRadiusDefault,
        );
        // Status yang sudah lewat masa berlaku diperlakukan sebagai kosong,
        // jadi form tidak menampilkan teks basi.
        final statusExpiresAt =
            DateTime.tryParse((res['status_expires_at'] ?? '') as String);
        final now = DateTime.now();
        _statusExpiresAt = statusExpiresAt;
        _statusEmoji = res['status_emoji'] as String?;
        _statusController.text = activeStatusText(
              text: res['status_text'] as String?,
              expiresAt: statusExpiresAt,
              now: now,
            ) ??
            '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String get _displayName {
    final u = _usernameController.text.trim();
    final f = _fullNameController.text.trim();
    return u.isNotEmpty ? u : (f.isNotEmpty ? f : '?');
  }

  Future<void> _pickAvatar() async {
    final uid = _uid;
    if (uid == null) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final isPng = (picked.mimeType ?? 'image/jpeg') == 'image/png';
      final ext = isPng ? 'png' : 'jpg';
      final path =
          '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('avatars').uploadBinary(path, bytes);
      final url = supabase.storage.from('avatars').getPublicUrl(path);
      await supabase
          .from('profiles')
          .update({'avatar_url': url})
          .eq('id', uid);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('upload_avatar_fail'))),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await supabase.from('profiles').update({
        'username': _usernameController.text.trim(),
        'full_name': _fullNameController.text.trim(),
        'avatar_url': _avatarUrl ?? '',
      }).eq('id', uid);
      // Phone disimpan terpisah (private_profiles) — upsert kalau baris
      // belum ada (mis. user lama sebelum migrasi).
      await supabase.from('private_profiles').upsert({
        'id': uid,
        'phone': _phoneController.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('profile_saved'))),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('profile_save_fail'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final accent = const Color(0xFF3D5AFE);
    return Card(
      color: context.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.more_horiz, size: 20, color: Color(0xFF3D5AFE)),
                const SizedBox(width: 8),
                Text(
                  context.l.t('status'),
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _statusController,
              style: TextStyle(color: context.textPrimary),
              maxLength: kStatusMaxLength,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: context.l.t('status_placeholder'),
                counterStyle: TextStyle(color: context.textFaded(0.5)),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final emoji in kStatusEmojiChoices)
                  _statusEmojiChip(context, emoji, accent),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.l.t('status_valid_for'),
              style: TextStyle(color: context.textFaded(0.7), fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final ttl in StatusTtl.values)
                  ChoiceChip(
                    label: Text(context.l.t(statusTtlKey(ttl))),
                    selected: _statusTtl == ttl,
                    onSelected: (_) => setState(() => _statusTtl = ttl),
                  ),
              ],
            ),
            if (_statusExpiresAt != null) ...[
              const SizedBox(height: 12),
              Text(
                context.l.t(
                  'status_expires_in',
                ).replaceAll('%d', _remainingStatusText()),
                style: TextStyle(color: context.textFaded(0.7), fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _savingStatus ? null : _saveStatus,
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    child: _savingStatus
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(context.l.t('status_save')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _savingStatus ? null : _clearStatus,
                    child: Text(context.l.t('status_clear')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusEmojiChip(BuildContext context, String emoji, Color accent) {
    final selected = _statusEmoji == emoji;
    return InkWell(
      onTap: () => setState(() => _statusEmoji = selected ? null : emoji),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? accent.withValues(alpha: 0.2) : Colors.transparent,
          border: Border.all(
            color: selected ? accent : context.textFaded(0.3),
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      ),
    );
  }

  /// Sisa masa berlaku status dalam bentuk ringkas (mis. "3j 12m").
  String _remainingStatusText() {
    final expires = _statusExpiresAt;
    if (expires == null) return '';
    final left = expires.difference(DateTime.now());
    if (left.isNegative) return '0m';
    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);
    return hours > 0 ? '${hours}j ${minutes}m' : '${minutes}m';
  }

  Future<void> _saveStatus() async {
    setState(() => _savingStatus = true);
    final ok = await StatusService.setStatus(
      text: _statusController.text,
      emoji: _statusEmoji,
      ttl: _statusTtl,
    );
    if (!mounted) return;
    setState(() {
      _savingStatus = false;
      if (ok) _statusExpiresAt = DateTime.now().add(_statusTtl.duration);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l.t(ok ? 'status_saved' : 'status_save_fail')),
      ),
    );
  }

  Future<void> _clearStatus() async {
    setState(() => _savingStatus = true);
    final ok = await StatusService.clearStatus();
    if (!mounted) return;
    setState(() {
      _savingStatus = false;
      if (ok) {
        _statusExpiresAt = null;
        _statusEmoji = null;
        _statusController.clear();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l.t(ok ? 'status_cleared' : 'status_save_fail')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButtonWidget(icon: Icons.menu),
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(context.l.t('profile')),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3D5AFE)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _uploadingAvatar ? null : _pickAvatar,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            UserAvatar(
                              name: _displayName,
                              avatarUrl: _avatarUrl,
                              radius: 44,
                              backgroundColor: const Color(0xFF3D5AFE),
                            ),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0xFF3D5AFE),
                                shape: BoxShape.circle,
                              ),
                              child: _uploadingAvatar
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l.t('edit_avatar_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.textFaded(0.5),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
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
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: context.textPrimary),
                      decoration: InputDecoration(
                        labelText: context.l.t('phone_optional'),
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                    ),
                    if (_email != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Email: $_email',
                        style: TextStyle(
                          color: context.textFaded(0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildStatusCard(context),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3D5AFE),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(context.l.t('save_profile')),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh
                          .withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SwitchListTile(
                        value: _batterySaver,
                        onChanged: _toggleBatterySaver,
                        activeThumbColor: const Color(0xFF3D5AFE),
                        secondary: Icon(
                          Icons.battery_saver,
                          color: _batterySaver
                              ? const Color(0xFF3D5AFE)
                              : context.textFaded(0.5),
                        ),
                        title: Text(
                          context.l.t('battery_saver'),
                          style: TextStyle(color: context.textPrimary),
                        ),
                        subtitle: Text(
                          context.l.t('battery_saver_sub'),
                          style: TextStyle(
                            color: context.textFaded(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh
                          .withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Icon(
                                  Icons.brightness_6_outlined,
                                  color: context.accentColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  context.l.t('theme'),
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<ThemeMode>(
                              segments: [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text(context.l.t('theme_system')),
                                  icon: const Icon(Icons.brightness_auto),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text(context.l.t('theme_light')),
                                  icon: const Icon(Icons.light_mode),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text(context.l.t('theme_dark')),
                                  icon: const Icon(Icons.dark_mode),
                                ),
                              ],
                              selected: {_themeMode},
                              onSelectionChanged: (s) {
                                if (s.isNotEmpty) _setThemeMode(s.first);
                              },
                            ),
                            const Divider(height: 28, color: Colors.white12),
                            Row(
                              children: [
                                Icon(
                                  Icons.language,
                                  color: context.accentColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  context.l.t('select_language'),
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<AppLocale>(
                              segments: const [
                                ButtonSegment(
                                  value: AppLocale.id,
                                  label: Text('Indonesia'),
                                  icon: Icon(Icons.translate),
                                ),
                                ButtonSegment(
                                  value: AppLocale.en,
                                  label: Text('English'),
                                  icon: Icon(Icons.translate),
                                ),
                              ],
                              selected: {_locale},
                              onSelectionChanged: (s) {
                                if (s.isNotEmpty) _setLocale(s.first);
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh
                          .withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SwitchListTile(
                        value: _alwaysShare,
                        onChanged: _toggleAlwaysShare,
                        activeThumbColor: const Color(0xFF3D5AFE),
                        secondary: Icon(
                          Icons.all_inclusive,
                          color: _alwaysShare
                              ? const Color(0xFF3D5AFE)
                              : context.textFaded(0.5),
                        ),
                        title: Text(
                          context.l.t('always_share'),
                          style: TextStyle(color: context.textPrimary),
                        ),
                        subtitle: Text(
                          context.l.t('always_share_sub'),
                          style: TextStyle(
                            color: context.textFaded(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh
                          .withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: _nearbyAlerts,
                            onChanged: _toggleNearbyAlerts,
                            activeThumbColor: const Color(0xFF3D5AFE),
                            secondary: Icon(
                              Icons.notifications_active_outlined,
                              color: _nearbyAlerts
                                  ? const Color(0xFF3D5AFE)
                                  : context.textFaded(0.5),
                            ),
                            title: Text(
                              context.l.t('nearby_alert'),
                              style: TextStyle(color: context.textPrimary),
                            ),
                            subtitle: Text(
                              context.l.t('nearby_alert_sub'),
                              style: TextStyle(
                                color: context.textFaded(0.5),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (_nearbyAlerts) ...[
                            const Divider(height: 1, color: Colors.white12),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.radar,
                                    color: context.accentColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      context.l.t('nearby_radius'),
                                      style: TextStyle(
                                        color: context.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatDistance(_nearbyRadius),
                                    style: TextStyle(
                                      color: context.accentColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Slider(
                              value: _nearbyRadius.toDouble(),
                              min: nearbyRadiusMin.toDouble(),
                              max: nearbyRadiusMax.toDouble(),
                              divisions: 18,
                              label: formatDistance(_nearbyRadius),
                              activeColor: const Color(0xFF3D5AFE),
                              onChanged: (v) =>
                                  setState(() => _nearbyRadius = v.round()),
                              onChangeEnd: _setNearbyRadius,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _logout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.logout),
                      label: Text(context.l.t('logout')),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

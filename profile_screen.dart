import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'money.dart';
import 'auth_api.dart';
import '../services/media_url.dart';
import '../widgets/auth_components.dart';
import '../widgets/withdrawal_pin_sheet.dart';
import 'settings_screen.dart';
import 'subscriptions_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.api,
    required this.token,
    required this.user,
    required this.onLogout,
    required this.onDeleted,
  });

  final AuthApi api;
  final String token;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;
  final VoidCallback onDeleted;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _currency = TextEditingController();
  final _email = TextEditingController();
  final _country = TextEditingController();

  bool _editing = false;
  bool _saving = false;
  bool _mediaBusy = false;
  bool _securityBusy = false;

  Map<String, dynamic> get _user => widget.user;

  @override
  void initState() {
    super.initState();
    _fillControllers();
    _refreshProfile();
  }

  void _fillControllers() {
    _name.text = _user['full_name']?.toString() ?? '';
    _username.text = _user['username']?.toString() ?? '';
    _phone.text = _user['phone']?.toString() ?? '';
    _currency.text = _user['preferred_currency']?.toString() ?? '';
    _email.text = _user['email']?.toString() ?? '';
    final countryName = _user['country_name']?.toString();
    final countryCode = _user['country_code']?.toString() ?? '';
    _country.text = countryName == null || countryName.isEmpty
        ? (countryCode.isEmpty ? 'Not set' : countryCode)
        : '$countryName ($countryCode)';
  }

  Future<void> _refreshProfile() async {
    try {
      final response = await widget.api.get('me', widget.token);
      final data = response['data'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() {
          _user.addAll(data);
          _fillControllers();
        });
      }
    } on AuthException {
      // Keep the session profile visible when the device is offline.
    }
  }

  Future<void> _openSubscriptions() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionsScreen(
          api: widget.api,
          token: widget.token,
          user: _user,
        ),
      ),
    );
    if (mounted) {
      await _refreshProfile();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          api: widget.api,
          token: widget.token,
          user: _user,
          onLogout: widget.onLogout,
          onDeleted: widget.onDeleted,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _phone.dispose();
    _currency.dispose();
    _email.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final response = await widget.api.patch('me', widget.token, {
        'full_name': _name.text.trim(),
        'username': _username.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        if (_currency.text.trim().isNotEmpty)
          'preferred_currency': _currency.text.trim().toUpperCase(),
      });
      if (response['data'] is Map<String, dynamic>) {
        _user.addAll(response['data'] as Map<String, dynamic>);
      }
      if (mounted) {
        setState(() => _editing = false);
        _fillControllers();
        showAuthMessage(context, 'Profile updated.');
      }
    } on AuthException catch (error) {
      if (mounted) showAuthMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage(String type) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final image = picked.files.first;
      if (image.size > 5 * 1024 * 1024) {
        if (mounted)
          showAuthMessage(context, 'Choose an image smaller than 5 MB.');
        return;
      }
      setState(() => _mediaBusy = true);
      final response = await widget.api.uploadProfileImage(
        widget.token,
        type,
        image,
      );
      if (response['data'] is Map<String, dynamic>) {
        _user.addAll(response['data'] as Map<String, dynamic>);
      }
      if (mounted) {
        setState(() {});
        showAuthMessage(
          context,
          '${type == 'avatar' ? 'Profile photo' : 'Cover image'} updated.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) showAuthMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _removeImage(String type) async {
    try {
      final response = await widget.api.delete('me/media/$type', widget.token);
      if (response['data'] is Map<String, dynamic>) {
        _user.addAll(response['data'] as Map<String, dynamic>);
      }
      if (mounted) setState(() {});
    } on AuthException catch (error) {
      if (mounted) showAuthMessage(context, error.message);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Change password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your current password'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (value) => value == null || value.length < 10
                    ? 'Use at least 10 characters'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
                validator: (value) =>
                    value != next.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Update password'),
          ),
        ],
      ),
    );
    if (submit == true) {
      try {
        await widget.api.put('me/password', widget.token, {
          'current_password': current.text,
          'password': next.text,
          'password_confirmation': confirm.text,
        });
        if (mounted) showAuthMessage(context, 'Password updated.');
      } on AuthException catch (error) {
        if (mounted) showAuthMessage(context, error.message);
      }
    }
    current.dispose();
    next.dispose();
    confirm.dispose();
  }

  Future<void> _manageSecurityPin() async {
    if (_securityBusy) return;
    final pinIsSet = _user['security_pin_set'] == true;
    setState(() => _securityBusy = true);
    try {
      final saved = await showWithdrawalPinSheet(
        context,
        api: widget.api,
        token: widget.token,
        endpoint: 'me/security-pin',
        requireCurrentPin: pinIsSet,
        requireAccountPassword: !pinIsSet && _user['has_password'] == true,
        title: pinIsSet
            ? 'Choose a new withdrawal PIN'
            : 'Create a withdrawal PIN',
        onSuccess: (response) {
          final data = response['data'];
          if (mounted && data is Map) {
            setState(() => _user.addAll(Map<String, dynamic>.from(data)));
          }
        },
      );
      if (saved && mounted) {
        showAuthMessage(context, pinIsSet ? 'PIN updated.' : 'PIN saved.');
      }
    } finally {
      if (mounted) setState(() => _securityBusy = false);
    }
  }

  Future<void> _removeSecurityPin() async {
    final pin = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Remove withdrawal PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your current PIN to turn off withdrawal verification.',
            ),
            const SizedBox(height: 12),
            _pinField(pin, 'Current 4-digit PIN'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, pin.text),
            child: const Text('Remove PIN'),
          ),
        ],
      ),
    );
    if (code == null) {
      pin.dispose();
      return;
    }
    try {
      final response = await widget.api.delete(
        'me/security-pin',
        widget.token,
        body: {'current_pin': code},
      );
      if (response['data'] is Map<String, dynamic> && mounted) {
        setState(() => _user.addAll(response['data'] as Map<String, dynamic>));
        showAuthMessage(context, 'Withdrawal PIN removed.');
      }
    } on AuthException catch (error) {
      if (mounted) showAuthMessage(context, error.message);
    } finally {
      pin.dispose();
    }
  }

  Widget _pinField(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    obscureText: true,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 4,
    textAlign: TextAlign.center,
    decoration: InputDecoration(labelText: label, counterText: ''),
    validator:
        validator ??
        (value) => value == null || value.length != 4
            ? 'Enter exactly 4 digits.'
            : null,
  );

  Future<void> _setupTwoFactor() async {
    if (_securityBusy) return;
    setState(() => _securityBusy = true);
    try {
      final setup = await widget.api.post(
        'me/two-factor/setup',
        widget.token,
        const {},
      );
      final details = setup['data'];
      if (details is! Map<String, dynamic> || !mounted) return;
      final response = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TwoFactorSetupDialog(
          api: widget.api,
          token: widget.token,
          setup: details,
        ),
      );
      final data = response?['data'];
      final recoveryCodes = response?['recovery_codes'];
      if (data is Map<String, dynamic> && mounted) {
        setState(() => _user.addAll(data));
        if (recoveryCodes is List) await _showRecoveryCodes(recoveryCodes);
      }
    } on AuthException catch (error) {
      if (mounted) showAuthMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _securityBusy = false);
    }
  }

  Future<void> _showRecoveryCodes(List<dynamic> codes) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Save your recovery codes'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Each code works once if you lose access to Google Authenticator. Save these now; they will not be shown again.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                codes.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: codes.join('\n')));
              if (dialogContext.mounted) {
                showAuthMessage(dialogContext, 'Recovery codes copied.');
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy codes'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('I saved them'),
          ),
        ],
      ),
    );
  }

  Future<void> _disableTwoFactor() async {
    final code = TextEditingController();
    final enteredCode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Turn off authenticator verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Confirm with a current authenticator code or an unused recovery code.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: code,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              maxLength: 20,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'Authenticator or recovery code',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, code.text),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (enteredCode == null) {
      code.dispose();
      return;
    }
    setState(() => _securityBusy = true);
    try {
      final response = await widget.api.delete(
        'me/two-factor',
        widget.token,
        body: {'code': enteredCode},
      );
      if (response['data'] is Map<String, dynamic> && mounted) {
        setState(() => _user.addAll(response['data'] as Map<String, dynamic>));
        showAuthMessage(context, 'Authenticator verification disabled.');
      }
    } on AuthException catch (error) {
      if (mounted) showAuthMessage(context, error.message);
    } finally {
      code.dispose();
      if (mounted) setState(() => _securityBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final name = user['full_name']?.toString().trim() ?? '';
    final email = user['email']?.toString() ?? '';
    final avatar = MediaUrl.resolve(user['avatar']?.toString());
    final cover = MediaUrl.resolve(user['cover_image']?.toString());
    final countryName = user['country_name']?.toString();
    final countryCode = user['country_code']?.toString() ?? '';
    final country = (countryName == null || countryName.isEmpty)
        ? (countryCode.isEmpty ? 'Not set' : countryCode)
        : '$countryName ($countryCode)';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final subscriptionContext = user['subscription_context'] is Map
        ? Map<String, dynamic>.from(user['subscription_context'] as Map)
        : <String, dynamic>{};
    final activeSubscriptions =
        (subscriptionContext['active_marketplaces'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    final catalog = subscriptionContext['catalog'] is Map
        ? Map<String, dynamic>.from(subscriptionContext['catalog'] as Map)
        : <String, dynamic>{};
    final plansById = <String, Map<String, dynamic>>{};
    for (final group
        in (catalog['subscription_groups'] as List? ?? const [])
            .whereType<Map>()) {
      for (final plan
          in (group['plans'] as List? ?? const []).whereType<Map>()) {
        final id = plan['id']?.toString();
        if (id != null) plansById[id] = Map<String, dynamic>.from(plan);
      }
    }
    final hasAddonSubscription = activeSubscriptions.any((subscription) {
      final plan = plansById[subscription['subscription_plan_id']?.toString()];
      return plan?['addons'] == true || plan?['addons'] == 1;
    });

    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
        cardTheme: CardThemeData(
          color: theme.cardTheme.color,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(19),
            side: BorderSide(color: colors.outlineVariant),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: theme.inputDecorationTheme.fillColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: colors.primary, width: 1.4),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _editing ? 'Edit profile' : 'My profile',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (!_editing)
              IconButton(
                tooltip: 'Settings',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            if (_editing)
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _editing = false;
                        _fillControllers();
                      }),
                child: const Text('Cancel'),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () => setState(() => _editing = true),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshProfile,
          color: colors.primary,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 5, 16, 30),
                children: [
                  _ProfileHero(
                    name: name.isEmpty ? 'Your profile' : name,
                    username: user['username']?.toString() ?? '',
                    email: email,
                    avatarUrl: avatar,
                    coverUrl: cover,
                    verified: user['email_verified'] == true,
                  ),
                  const SizedBox(height: 15),
                  if (_editing) ...[
                    if (_mediaBusy)
                      Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          color: colors.primary,
                        ),
                      ),
                    _SectionCard(
                      title: 'Profile appearance',
                      subtitle:
                          'Add a photo and cover to personalize your profile.',
                      child: Column(
                        children: [
                          _MediaRow(
                            title: 'Profile photo',
                            url: avatar,
                            isAvatar: true,
                            busy: _mediaBusy,
                            onPick: () => _pickImage('avatar'),
                            onRemove: avatar == null
                                ? null
                                : () => _removeImage('avatar'),
                          ),
                          const Divider(height: 22),
                          _MediaRow(
                            title: 'Cover image',
                            url: cover,
                            busy: _mediaBusy,
                            onPick: () => _pickImage('cover'),
                            onRemove: cover == null
                                ? null
                                : () => _removeImage('cover'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Personal details',
                      subtitle:
                          'Keep your contact and account information current.',
                      child: Column(
                        children: [
                          _EditField(
                            controller: _name,
                            label: 'Full name',
                            icon: Icons.person_outline,
                          ),
                          _EditField(
                            controller: _username,
                            label: 'Username',
                            icon: Icons.alternate_email,
                          ),
                          _EditField(
                            controller: _email,
                            label: 'Email address',
                            icon: Icons.email_outlined,
                            readOnly: true,
                          ),
                          _EditField(
                            controller: _phone,
                            label: 'Phone number',
                            icon: Icons.phone_outlined,
                            keyboard: TextInputType.phone,
                          ),
                          _EditField(
                            controller: _country,
                            label: 'Country',
                            icon: Icons.public,
                            readOnly: true,
                          ),
                          _EditField(
                            controller: _currency,
                            label: 'Preferred currency',
                            icon: Icons.currency_exchange,
                            capitalization: TextCapitalization.characters,
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              icon: _saving
                                  ? SizedBox.square(
                                      dimension: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: Text(_saving ? 'Saving…' : 'Save changes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _SectionCard(
                      title: 'Personal details',
                      subtitle: 'Your profile and contact information.',
                      child: Column(
                        children: [
                          _DetailRow(
                            icon: Icons.person_outline,
                            label: 'Full name',
                            value: name,
                          ),
                          _DetailRow(
                            icon: Icons.alternate_email,
                            label: 'Username',
                            value: user['username']?.toString(),
                          ),
                          _DetailRow(
                            icon: Icons.email_outlined,
                            label: 'Email address',
                            value: email,
                            trailing: user['email_verified'] == true
                                ? _TinyStatus(
                                    label: 'Verified',
                                    color: colors.primary,
                                  )
                                : _TinyStatus(
                                    label: 'Unverified',
                                    color: colors.tertiary,
                                  ),
                          ),
                          _DetailRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone number',
                            value: user['phone']?.toString(),
                          ),
                          _DetailRow(
                            icon: Icons.public,
                            label: 'Country',
                            value: country,
                          ),
                          _DetailRow(
                            icon: Icons.currency_exchange,
                            label: 'Preferred currency',
                            value: user['preferred_currency']?.toString(),
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    _SectionCard(
                      title: 'My subscriptions',
                      subtitle: activeSubscriptions.isEmpty
                          ? 'Your active packages will appear here.'
                          : 'Your currently active earning packages and their terms.',
                      child: activeSubscriptions.isEmpty
                          ? _NoActiveSubscription(onBrowse: _openSubscriptions)
                          : Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < activeSubscriptions.length;
                                  index++
                                ) ...[
                                  _ActiveSubscriptionCard(
                                    subscription: activeSubscriptions[index],
                                    plan:
                                        plansById[activeSubscriptions[index]['subscription_plan_id']
                                            ?.toString()],
                                    preferredCurrency:
                                        user['preferred_currency']
                                            ?.toString() ??
                                        'USD',
                                    api: widget.api,
                                    formatDate: _formatDate,
                                  ),
                                  if (index < activeSubscriptions.length - 1)
                                    const SizedBox(height: 10),
                                ],
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _openSubscriptions,
                                    icon: const Icon(
                                      Icons.manage_accounts_outlined,
                                    ),
                                    label: const Text('Manage packages'),
                                  ),
                                ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Account overview',
                      child: Column(
                        children: [
                          _DetailRow(
                            icon: Icons.calendar_month_outlined,
                            label: 'Member since',
                            value: _formatDate(user['created_at']?.toString()),
                          ),
                          _DetailRow(
                            icon: Icons.verified_user_outlined,
                            label: 'Account status',
                            value: _statusLabel(user['status']?.toString()),
                            trailing: _StatusDot(
                              active:
                                  user['status'] == null ||
                                  user['status'] == 'active',
                            ),
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SectionCard(
                      title: 'Security centre',
                      subtitle: 'Manage the ways your account and earnings are protected.',
                      child: Column(
                        children: [
                          _SecurityAction(
                            icon: Icons.lock_reset_rounded,
                            title: 'Password',
                            subtitle: 'Change your account password',
                            onTap: _changePassword,
                          ),
                          const Divider(height: 1),
                          _SecurityAction(
                            icon: Icons.pin_rounded,
                            title: 'Withdrawal PIN',
                            subtitle: user['security_pin_set'] == true
                                ? 'A PIN is enabled for withdrawal requests'
                                : 'Add a 4-digit PIN for withdrawals',
                            trailing: Text(
                              user['security_pin_set'] == true
                                  ? 'Manage'
                                  : 'Set up',
                              style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            onTap: _securityBusy ? null : _manageSecurityPin,
                          ),
                          if (user['security_pin_set'] == true)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _securityBusy
                                    ? null
                                    : _removeSecurityPin,
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 17,
                                ),
                                label: const Text('Remove withdrawal PIN'),
                              ),
                            ),
                          const Divider(height: 1),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            secondary: _securityIcon(
                              context,
                              Icons.phonelink_lock_rounded,
                            ),
                            title: const Text(
                              'Google Authenticator',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              user['two_factor'] == true
                                  ? 'Extra sign-in verification is enabled'
                                  : 'Add a second verification step at sign in',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            value: user['two_factor'] == true,
                            activeColor: colors.primary,
                            onChanged: _securityBusy
                                ? null
                                : (enabled) => enabled
                                      ? _setupTwoFactor()
                                      : _disableTwoFactor(),
                          ),
                          if (_securityBusy)
                            Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                color: colors.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 13),
                  const _PrivacyNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _statusLabel(String? status) => switch (status) {
    'active' => 'Active',
    'pending' => 'Pending',
    'suspended' => 'Suspended',
    null || '' => 'Active',
    _ => status,
  };
}

class _TwoFactorSetupDialog extends StatefulWidget {
  const _TwoFactorSetupDialog({
    required this.api,
    required this.token,
    required this.setup,
  });
  final AuthApi api;
  final String token;
  final Map<String, dynamic> setup;

  @override
  State<_TwoFactorSetupDialog> createState() => _TwoFactorSetupDialogState();
}

class _TwoFactorSetupDialogState extends State<_TwoFactorSetupDialog> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length != 6) {
      showAuthMessage(
        context,
        'Enter the 6-digit code shown in your authenticator app.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.api.post(
        'me/two-factor/confirm',
        widget.token,
        {'code': _code.text.trim()},
      );
      if (mounted) Navigator.pop(context, result);
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showAuthMessage(context, error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final secret = widget.setup['secret']?.toString() ?? '';
    final uri = widget.setup['otpauth_uri']?.toString() ?? '';
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: screen.width < 432 ? screen.width - 40 : 392,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screen.height * .84),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Set up Google Authenticator',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Scan this QR code with Google Authenticator, or enter the setup key manually.',
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: SizedBox.square(
                          dimension: 190,
                          child: QrImageView(data: uri),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        secret,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: secret));
                          if (context.mounted)
                            showAuthMessage(context, 'Setup key copied.');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy setup key'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: '6-digit authenticator code',
                          counterText: '',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      icon: _busy
                          ? SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.verified_user_outlined),
                      label: Text(
                        _busy ? 'Verifying…' : 'Enable 2-step verification',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.username,
    required this.email,
    required this.avatarUrl,
    required this.coverUrl,
    required this.verified,
  });

  final String name;
  final String username;
  final String email;
  final String? avatarUrl;
  final String? coverUrl;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover area. The gradient provides a polished fallback when no
          // custom cover image has been uploaded.
          SizedBox(
            height: 148,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary,
                        scheme.primaryContainer,
                        scheme.secondary,
                      ],
                    ),
                    image: coverUrl == null
                        ? null
                        : DecorationImage(
                            image: NetworkImage(coverUrl!),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                if (coverUrl == null) ...[
                  Positioned(
                    right: -24,
                    top: -58,
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.onPrimary.withValues(alpha: .16),
                          width: 22,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 42,
                    bottom: -64,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.onPrimary.withValues(alpha: .08),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: 18,
                    child: Icon(
                      Icons.person_pin_circle_outlined,
                      size: 42,
                      color: scheme.onPrimary.withValues(alpha: .30),
                    ),
                  ),
                ],
                if (coverUrl != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.scrim.withValues(alpha: .04),
                          scheme.scrim.withValues(alpha: .28),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 1),
            child: Transform.translate(
              offset: const Offset(0, -39),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: .13),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 37,
                      backgroundColor: scheme.secondaryContainer,
                      backgroundImage: avatarUrl == null
                          ? null
                          : NetworkImage(avatarUrl!),
                      child: avatarUrl == null
                          ? Icon(
                              Icons.person_outline_rounded,
                              size: 39,
                              color: scheme.onSecondaryContainer,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w900,
                            height: 1.12,
                          ),
                        ),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.verified_rounded,
                          size: 21,
                          color: scheme.primary,
                        ),
                      ],
                    ],
                  ),
                  if (username.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      '@$username',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          Icons.mail_outline_rounded,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (verified) ...[
                    const SizedBox(height: 12),
                    _TinyStatus(label: 'Email verified', color: scheme.primary),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: .02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }
}

class _NoActiveSubscription extends StatelessWidget {
  const _NoActiveSubscription({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.layers_outlined, color: colors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'No active package',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Join a package to unlock its app review or ad sharing tasks.',
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onBrowse,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Browse packages'),
          ),
        ],
      ),
    );
  }
}

class _ActiveSubscriptionCard extends StatelessWidget {
  const _ActiveSubscriptionCard({
    required this.subscription,
    required this.plan,
    required this.preferredCurrency,
    required this.api,
    required this.formatDate,
  });

  final Map<String, dynamic> subscription;
  final Map<String, dynamic>? plan;
  final String preferredCurrency;
  final AuthApi api;
  final String Function(String?) formatDate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final source = plan ?? const <String, dynamic>{};
    final groupKey =
        subscription['group_key']?.toString() ??
        source['group_key']?.toString() ??
        '';
    final planName =
        source['name']?.toString() ??
        subscription['plan_name']?.toString() ??
        'Marketplace package';
    final sourceCurrency = source['currency']?.toString() ?? 'USD';
    final price = source['price_minor'];
    final billingInterval = source['billing_interval']?.toString();
    final durationCount = (source['duration_count'] as num?)?.toInt() ?? 1;
    final withdrawalDays = (source['withdrawal_days'] as List? ?? const [])
        .map((day) => day.toString())
        .where((day) => day.isNotEmpty)
        .toList();
    final groupLabel = switch (groupKey) {
      'group_a' => 'Ad sharing',
      'group_b' => 'Store app reviews',
      'group_c' => 'Apple app reviews',
      _ => 'Marketplace access',
    };
    final intervalUnit = switch (billingInterval?.toLowerCase()) {
      'monthly' => 'month',
      'weekly' => 'week',
      'quarterly' => 'quarter',
      'yearly' || 'annual' => 'year',
      _ => null,
    };
    final durationLabel = intervalUnit == null
        ? null
        : '$durationCount $intervalUnit${durationCount == 1 ? '' : 's'}';
    final endsAt = formatDate(subscription['ends_at']?.toString());
    final startsAt = formatDate(subscription['starts_at']?.toString());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  groupKey == 'group_a'
                      ? Icons.campaign_outlined
                      : Icons.rate_review_outlined,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      planName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      groupLabel,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontSize: 9,
                    letterSpacing: .5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (price != null) ...[
            const SizedBox(height: 13),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    moneyConverted(
                      api,
                      price,
                      sourceCurrency,
                      source['currency_minor_units'],
                      preferredCurrency,
                      isMinor: true,
                    ),
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (durationLabel != null)
                  Text(
                    'Term · $durationLabel',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showSubscriptionFeatures(
                context,
                planName,
                [
                  if (startsAt.isNotEmpty)
                    const MapEntry(
                      Icons.play_circle_outline_rounded,
                      'Started',
                    ),
                  if (endsAt.isNotEmpty)
                    const MapEntry(
                      Icons.event_available_outlined,
                      'Valid until',
                    ),
                  if (source['max_review_tasks'] is num &&
                      (source['max_review_tasks'] as num).toInt() > 0)
                    MapEntry(
                      Icons.rate_review_outlined,
                      '${source['max_review_tasks']} reviews',
                    ),
                  if (source['max_ad_shares'] is num &&
                      (source['max_ad_shares'] as num).toInt() > 0)
                    MapEntry(
                      Icons.campaign_outlined,
                      '${source['max_ad_shares']} ad shares',
                    ),
                  if (source['daily_task_limit'] is num &&
                      (source['daily_task_limit'] as num).toInt() > 0)
                    MapEntry(
                      Icons.today_outlined,
                      '${source['daily_task_limit']} tasks daily',
                    ),
                  if (source['daily_revenue_minor'] is num &&
                      (source['daily_revenue_minor'] as num).toInt() > 0)
                    MapEntry(
                      Icons.trending_up_rounded,
                      'Daily earning limit: ${moneyConverted(api, source['daily_revenue_minor'], sourceCurrency, source['currency_minor_units'], preferredCurrency, isMinor: true)}',
                    ),
                  if (source['minimum_withdrawal_minor'] is num &&
                      (source['minimum_withdrawal_minor'] as num).toInt() > 0)
                    MapEntry(
                      Icons.account_balance_wallet_outlined,
                      'Minimum withdrawal: ${moneyConverted(api, source['minimum_withdrawal_minor'], sourceCurrency, source['currency_minor_units'], preferredCurrency, isMinor: true)}',
                    ),
                  if (withdrawalDays.isNotEmpty)
                    MapEntry(
                      Icons.calendar_month_outlined,
                      'Withdrawal days: ${withdrawalDays.join(' & ')}',
                    ),
                ],
                startedAt: startsAt,
                validUntil: endsAt,
              ),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('View package features'),
            ),
          ),
        ],
      ),
    );
  }
}

void _showSubscriptionFeatures(
  BuildContext context,
  String planName,
  List<MapEntry<IconData, String>> features, {
  required String startedAt,
  required String validUntil,
}) {
  final colors = Theme.of(context).colorScheme;
  final items = <MapEntry<IconData, String>>[
    if (startedAt.isNotEmpty)
      MapEntry(Icons.play_circle_outline_rounded, 'Started: $startedAt'),
    if (validUntil.isNotEmpty)
      MapEntry(Icons.event_available_outlined, 'Valid until: $validUntil'),
    ...features.where(
      (item) =>
          item.key != Icons.play_circle_outline_rounded &&
          item.key != Icons.event_available_outlined,
    ),
  ];

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$planName features'),
      content: SizedBox(
        width: 420,
        child: items.isEmpty
            ? const Text(
                'No additional feature details are available for this package.',
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colors.outlineVariant),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.key, size: 19, color: colors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.value,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _SubscriptionInfoPill extends StatelessWidget {
  const _SubscriptionInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.last = false,
  });
  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value == null || value!.isEmpty ? 'Not added' : value!,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        if (!last) Divider(height: 1, color: colors.outlineVariant),
      ],
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.controller,
    required this.label,
    required this.icon,
    this.readOnly = false,
    this.keyboard,
    this.capitalization = TextCapitalization.none,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool readOnly;
  final TextInputType? keyboard;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboard,
      textCapitalization: capitalization,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19),
        helperText: label == 'Country'
            ? 'Country is fixed from registration.'
            : null,
      ),
    ),
  );
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.title,
    required this.onPick,
    required this.busy,
    this.url,
    this.isAvatar = false,
    this.onRemove,
  });
  final String title;
  final String? url;
  final bool isAvatar;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = isAvatar
        ? CircleAvatar(
            radius: 25,
            backgroundColor: colors.primaryContainer,
            backgroundImage: url == null ? null : NetworkImage(url!),
            child: url == null
                ? Icon(Icons.person_outline, color: colors.onPrimaryContainer)
                : null,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: SizedBox(
              width: 76,
              height: 48,
              child: url == null
                  ? ColoredBox(
                      color: colors.primaryContainer,
                      child: Icon(
                        Icons.panorama_outlined,
                        color: colors.onPrimaryContainer,
                      ),
                    )
                  : Image.network(url!, fit: BoxFit.cover),
            ),
          );
    return Row(
      children: [
        preview,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: busy ? null : onPick,
          child: Text(url == null ? 'Add' : 'Change'),
        ),
        if (onRemove != null)
          IconButton(
            onPressed: busy ? null : onRemove,
            tooltip: 'Remove $title',
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
          ),
      ],
    );
  }
}

class _SecurityAction extends StatelessWidget {
  const _SecurityAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: _securityIcon(context, icon),
    title: Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w800,
        fontSize: 14,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
      ),
    ),
    trailing:
        trailing ??
        Icon(
          Icons.chevron_right_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
    onTap: onTap,
  );
}

Widget _securityIcon(BuildContext context, IconData icon) => Container(
  width: 42,
  height: 42,
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.primaryContainer,
    borderRadius: BorderRadius.circular(13),
  ),
  child: Icon(
    icon,
    color: Theme.of(context).colorScheme.onPrimaryContainer,
    size: 21,
  ),
);

class _TinyStatus extends StatelessWidget {
  const _TinyStatus({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = active ? colors.primary : colors.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          active ? 'Active' : 'Review',
          style: TextStyle(
            color: statusColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: colors.onPrimaryContainer,
            size: 19,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your personal information is used to manage your account. Keep your password, withdrawal PIN, and authenticator recovery codes private.',
              style: TextStyle(
                color: colors.onPrimaryContainer,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

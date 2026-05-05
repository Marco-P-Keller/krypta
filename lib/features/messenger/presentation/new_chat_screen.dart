import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/platform/clipboard_helper.dart';
import '../../../theme/app_colors.dart';
import '../data/models/chat_model.dart';
import '../logic/messenger_provider.dart';
import 'widgets/qr_display_sheet.dart';

class NewChatScreen extends StatefulWidget {
  final void Function(Chat chat) onChatCreated;
  final VoidCallback onBack;
  final VoidCallback onScanQr;

  const NewChatScreen({
    super.key,
    required this.onChatCreated,
    required this.onBack,
    required this.onScanQr,
  });

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _contactIdController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _contactIdController.dispose();
    super.dispose();
  }

  Future<void> _addContact() async {
    final id = _contactIdController.text.trim();
    if (id.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final messenger = context.read<MessengerProvider>();

    if (id == messenger.userId) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = AppLocalizations.of(context)!.cannotAddYourself;
        });
      }
      return;
    }

    final contact = await messenger.addContact(id);
    if (contact == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = AppLocalizations.of(context)!.userNotFound;
        });
      }
      return;
    }

    if (!mounted) return;
    final name = await _showNameDialog(context, contact.shortId);
    if (!mounted) return;

    if (name != null && name.isNotEmpty) {
      await messenger.renameContact(contact.id, name);
    }

    final chat = messenger.getOrCreateChat(
      messenger.contactForId(contact.id) ?? contact,
    );
    if (mounted) {
      widget.onChatCreated(chat);
    }
  }

  Future<String?> _showNameDialog(BuildContext context, String shortId) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.nameThisContact),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.nameContactHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'ID: $shortId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: AppColors.textTertiaryDark,
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: l10n.nameContactPlaceholder,
                prefixIcon: const Icon(Icons.person_outline, size: 20),
              ),
              onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l10n.skip),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = context.watch<MessengerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newChat),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: widget.onBack,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QR actions
            Row(
              children: [
                Expanded(
                  child: _QrActionCard(
                    icon: Icons.qr_code_rounded,
                    label: l10n.myQrCode,
                    color: AppColors.primary,
                    onTap: () async {
                      if (messenger.userId != null) {
                        final pubKey = await messenger.getIdentityPublicKey();
                        if (pubKey != null && context.mounted) {
                          QrDisplaySheet.show(
                            context,
                            userId: messenger.userId!,
                            publicKey: pubKey,
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QrActionCard(
                    icon: Icons.qr_code_scanner_rounded,
                    label: l10n.scanQr,
                    color: AppColors.success,
                    onTap: widget.onScanQr,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Your ID (copyable)
            if (messenger.userId != null) ...[
              Text(
                l10n.userIdLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  // M2-Client: ephemeral copy with auto-clear.
                  ClipboardHelper.copyEphemeral(messenger.userId!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.userIdCopied)),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceElevatedDark
                        : AppColors.surfaceElevatedLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          messenger.userId!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    letterSpacing: 0.5,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.copy, size: 16, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],

            // Manual ID input
            Text(
              l10n.addContactById,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactIdController,
              decoration: InputDecoration(
                hintText: l10n.contactIdHint,
                errorText: _error,
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded),
                        onPressed: _addContact,
                      ),
              ),
              onSubmitted: (_) => _addContact(),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 28),

            // Existing contacts
            if (messenger.contacts.isNotEmpty) ...[
              Text(
                l10n.contacts,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: messenger.contacts.length,
                  itemBuilder: (context, index) {
                    final contact = messenger.contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        child: Text(
                          contact.displayName[0].toUpperCase(),
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ),
                      title: Text(contact.displayName),
                      subtitle: Text(
                        contact.shortId,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                      ),
                      onTap: () {
                        final chat = messenger.getOrCreateChat(contact);
                        widget.onChatCreated(chat);
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QrActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QrActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceElevatedDark
              : AppColors.surfaceElevatedLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

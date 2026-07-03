// lib/screens/contact/contact_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

const _kPrimary = Color(0xFF0F766E);
const _kAccent = Color(0xFF14B8A6);
const _kDark = Color(0xFF0D1B2A);
const _kBg = Color(0xFFF0F4F8);
const _kCard = Colors.white;
const _kGreen = Color(0xFF16A34A);
const _kSurface = Color(0xFFF8FAFC);
const _kBorder = Color(0xFFE2E8F0);
const _kTextMuted = Color(0xFF64748B);
const _kTextDim = Color(0xFF94A3B8);

// ── Real contact details ────────────────────────────────────────────────────
const _kSupportEmail = 'kotokawilson@gmail.com';
const _kSupportPhoneDisplay = '025 721 9035';
const _kSupportPhoneDial = '+233257219035'; // used for tel:
const _kWhatsappNumber = '233257219035'; // no + or leading zero, for wa.me

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  bool _navigatingToChat = false;

  void _openChat() {
    if (_navigatingToChat) return;
    _navigatingToChat = true;
    HapticFeedback.selectionClick();
    context.go('/chat');
    // reset the guard shortly after, since go() doesn't return a Future like push()
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _navigatingToChat = false;
    });
  }

  static const _faqs = [
    (
      'How do I pay my deposit?',
      'Go to your room booking, tap "Continue to Payment", choose Mobile Money, and follow the prompt on your phone.'
    ),
    (
      'Can I visit a hostel before booking?',
      'Yes — use the "Pre-book · Register Interest" button on any room to schedule a visit before paying.'
    ),
    (
      'What happens if I need a refund?',
      'Contact support via chat or email with your booking reference, and our team will review it with the landlord.'
    ),
  ];

  Future<void> _launch(String url, {String? failMessage}) async {
    final uri = Uri.parse(url);
    HapticFeedback.selectionClick();
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      _showSnack(
        failMessage ?? 'Could not open that link on this device.',
        isError: true,
      );
    }
  }

  void _copyToClipboard(String value, String label) {
    HapticFeedback.mediumImpact();
    Clipboard.setData(ClipboardData(text: value));
    _showSnack('$label copied to clipboard ✓');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? const Color(0xFFDC2626) : _kDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _kDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Contact Us',
            style: TextStyle(
                color: _kDark, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          // ── Primary: chat (live status pulled from Firestore) ─────────────
          _ChatSupportCard(
            onTap: _openChat,
          ),
          const SizedBox(height: 24),

          const _SectionLabel('Other Ways to Reach Us'),
          _ContactTile(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: _kSupportEmail,
            color: _kPrimary,
            onTap: () => _launch(
              'mailto:$_kSupportEmail?subject=RoomzyFind%20Support',
              failMessage: 'No email app found on this device.',
            ),
            onLongPress: () => _copyToClipboard(_kSupportEmail, 'Email'),
          ),
          const SizedBox(height: 10),
          _ContactTile(
            icon: Icons.phone_outlined,
            label: 'Call',
            value: _kSupportPhoneDisplay,
            color: const Color(0xFF2563EB),
            onTap: () => _launch('tel:$_kSupportPhoneDial'),
            onLongPress: () =>
                _copyToClipboard(_kSupportPhoneDisplay, 'Phone number'),
          ),
          const SizedBox(height: 10),
          _ContactTile(
            icon: Icons.chat_rounded,
            label: 'WhatsApp',
            value: _kSupportPhoneDisplay,
            color: const Color(0xFF25D366),
            onTap: () => _launch(
              'https://wa.me/$_kWhatsappNumber?text=Hi%2C%20I%20need%20help%20with%20RoomzyFind',
              failMessage: 'WhatsApp is not installed on this device.',
            ),
            onLongPress: () =>
                _copyToClipboard(_kSupportPhoneDisplay, 'WhatsApp number'),
          ),
          const SizedBox(height: 28),

          const _SectionLabel('Frequently Asked'),
          Container(
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: _faqs
                  .map((f) => _FaqTile(question: f.$1, answer: f.$2))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat card with live "online" pulled from real chat activity ──────────────
class _ChatSupportCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ChatSupportCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kPrimary, _kAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: _kPrimary.withOpacity(0.3),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Row(children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: 24),
              ),
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: const Color(0xFF69F0AE),
                  shape: BoxShape.circle,
                  border: Border.all(color: _kPrimary, width: 2),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chat with Support',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                if (uid != null)
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(uid)
                        .snapshots(),
                    builder: (_, snap) {
                      final unread =
                          snap.data?.data()?['unreadByStudent'] as bool? ??
                              false;
                      return Text(
                        unread
                            ? 'You have a new reply waiting'
                            : 'Usually replies within a few hours',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12.5),
                      );
                    },
                  )
                else
                  const Text('Usually replies within a few hours',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded,
              color: Colors.white, size: 16),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kTextMuted,
                letterSpacing: 0.4)),
      );
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _kTextDim,
                          fontWeight: FontWeight.w600)),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: _kDark)),
                ],
              ),
            ),
            if (onLongPress != null)
              Icon(Icons.copy_rounded, color: _kTextDim, size: 16),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: _kTextDim),
          ]),
        ),
      );
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(question,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700, color: _kDark)),
          iconColor: _kPrimary,
          collapsedIconColor: _kTextDim,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(answer,
                  style: const TextStyle(
                      fontSize: 13, color: _kTextMuted, height: 1.6)),
            ),
          ],
        ),
      );
}

// lib/widgets/hostels_hero.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HostelsHero extends StatefulWidget {
  final Function(String query, double? maxPrice, String duration)
      onSearchChanged;

  const HostelsHero({
    super.key,
    required this.onSearchChanged,
  });

  @override
  State<HostelsHero> createState() => _HostelsHeroState();
}

class _HostelsHeroState extends State<HostelsHero> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  String _selectedDuration = 'Per month';
  final List<String> _durations = ['Per month', 'Per semester', 'Per year'];

  void _triggerSearch() {
    final raw = _budgetController.text.replaceAll(',', '').trim();
    final budget = double.tryParse(raw);
    widget.onSearchChanged(
      _searchController.text.trim(),
      budget,
      _selectedDuration,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 800;
    final isMedium = width > 500;

    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/hostel.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.72),
              Colors.black.withValues(alpha: 0.60),
            ],
          ),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 64 : 20,
          vertical: isWide ? 80 : 52,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                /// Title
                Text(
                  'Find Your Perfect\nHostel or Apartment',
                  style: TextStyle(
                    fontSize: isWide ? 52 : (isMedium ? 40 : 32),
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  'Search by school, hostel name, or location\nand filter by your budget to find the best match.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: isMedium ? 16 : 14,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 32),

                /// Search Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// ── Search row ───────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _SearchField(
                              controller: _searchController,
                              hint: 'School, hostel or apartment name…',
                              onChanged: (_) => _triggerSearch(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _SearchButton(onTap: _triggerSearch),
                        ],
                      ),

                      const SizedBox(height: 14),

                      /// ── Budget + Duration row ────────────────────────
                      isMedium
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _BudgetField(
                                    controller: _budgetController,
                                    onChanged: (_) => _triggerSearch(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: _DurationDropdown(
                                    value: _selectedDuration,
                                    items: _durations,
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedDuration = val);
                                        _triggerSearch();
                                      }
                                    },
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _BudgetField(
                                  controller: _budgetController,
                                  onChanged: (_) => _triggerSearch(),
                                ),
                                const SizedBox(height: 12),
                                _DurationDropdown(
                                  value: _selectedDuration,
                                  items: _durations,
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedDuration = val);
                                      _triggerSearch();
                                    }
                                  },
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Search Field ─────────────────────────────────────────────────────────────
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Function(String) onChanged;
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF0D1B2A),
            fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
          prefixIcon:
              const Icon(Icons.search_rounded, color: Colors.black38, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );
}

// ─── Search Button ────────────────────────────────────────────────────────────
class _SearchButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchButton({required this.onTap});

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F766E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Row(
          children: [
            Icon(Icons.search, size: 18),
            SizedBox(width: 8),
            Text(
              'Search',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      );
}

// ─── Budget Field ─────────────────────────────────────────────────────────────
class _BudgetField extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onChanged;
  const _BudgetField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MY BUDGET (GH₵)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. 1500',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 14,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'GH₵',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.12),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF4ade80), width: 1.5),
              ),
            ),
          ),
        ],
      );
}

// ─── Duration Dropdown ────────────────────────────────────────────────────────
class _DurationDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final Function(String?) onChanged;
  const _DurationDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DURATION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 7),
          DropdownButtonFormField<String>(
            value: value,
            dropdownColor: const Color(0xFF0D2B2A),
            style: const TextStyle(
                fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white54, size: 20),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.12),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF4ade80)),
              ),
            ),
            items: items
                .map((d) => DropdownMenuItem(
                      value: d,
                      child: Text(d,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      );
}

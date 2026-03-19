import 'package:flutter/material.dart';

import 'package:roomzy_find/widgets/navbar.dart';
import 'package:roomzy_find/widgets/hostels_hero.dart';
import 'package:roomzy_find/widgets/hostels_list.dart';
import 'package:roomzy_find/widgets/footer.dart';

class HostelsScreen extends StatefulWidget {
  const HostelsScreen({super.key});

  @override
  State<HostelsScreen> createState() => _HostelsScreenState();
}

class _HostelsScreenState extends State<HostelsScreen> {
  String _searchQuery = '';

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      /// NAVBAR
      appBar: const Navbar(),

      /// MOBILE DRAWER
      endDrawer: const NavbarDrawer(),

      /// PAGE BODY
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            /// HERO SECTION
            HostelsHero(
              onSearchChanged: _onSearchChanged,
            ),

            const SizedBox(height: 40),

            /// HOSTELS LIST
            HostelsList(
              searchQuery: _searchQuery,
            ),

            const SizedBox(height: 60),

            /// FOOTER
            const Footer(),
          ],
        ),
      ),
    );
  }
}

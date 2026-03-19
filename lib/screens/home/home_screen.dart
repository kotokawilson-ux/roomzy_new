import 'package:flutter/material.dart';

import 'package:roomzy_find/widgets/navbar.dart';
import 'package:roomzy_find/widgets/hero_section.dart';
import 'package:roomzy_find/widgets/popular_properties.dart';
import 'package:roomzy_find/widgets/features_section.dart';
import 'package:roomzy_find/widgets/about_section.dart';
import 'package:roomzy_find/widgets/testimonials_section.dart';
import 'package:roomzy_find/widgets/footer.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      /// NAVBAR
      appBar: Navbar(),

      /// MOBILE DRAWER
      endDrawer: NavbarDrawer(),

      /// PAGE BODY
      body: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HeroSection(),
            PopularProperties(),
            FeaturesSection(),
            AboutSection(),
            TestimonialsSection(),
            Footer(),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class HostelsHero extends StatefulWidget {
  final Function(String) onSearchChanged;

  const HostelsHero({
    super.key,
    required this.onSearchChanged,
  });

  @override
  State<HostelsHero> createState() => _HostelsHeroState();
}

class _HostelsHeroState extends State<HostelsHero> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final searchWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.9;

    return Stack(
      children: [
        /// Background Image
        Container(
          height: 400,
          width: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/hostel.jpg'),
              fit: BoxFit.cover,
            ),
          ),
        ),

        /// Overlay
        Container(
          height: 400,
          width: double.infinity,
          color: Colors.black.withOpacity(0.5),
        ),

        /// Content
        SizedBox(
          height: 400,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// Title
                  Text(
                    'Find Your Perfect Hostel/Apartment',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.6),
                          offset: const Offset(0, 3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// Search
                  SizedBox(
                    width: searchWidth,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: widget.onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Enter school/hostel/apartment name',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            widget.onSearchChanged(_searchController.text);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 24,
                            ),
                          ),
                          child: const Icon(Icons.search),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

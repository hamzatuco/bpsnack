import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SlideData {
  final String? backgroundUrl;
  final Color overlayColor;
  final String title;
  final String desc;
  final bool isLeft;
  final CrossAxisAlignment crossAlign;
  final List<String> productUrls;
  final int? price; // Add price property
  SlideData({
    required this.backgroundUrl,
    required this.overlayColor,
    required this.title,
    required this.desc,
    required this.isLeft,
    required this.crossAlign,
    required this.productUrls,
    required this.price, // Add price to constructor
  });
}

Future<List<SlideData>> _fetchSlideData(List<QueryDocumentSnapshot> docs) async {
  final storage = FirebaseStorage.instance;
  return await Future.wait(docs.map((snapDoc) async {
    final data = snapDoc.data() as Map<String, dynamic>;
    // background downloadURL
    String? bgUrl;
    if (data['backgroundImagePath'] != null) {
      bgUrl = await storage.refFromURL(data['backgroundImagePath'] as String).getDownloadURL();
    }
    // overlay opacity
    final opacity = (data['opacity'] as num? ?? 0).toDouble().clamp(0,100) / 100;
    // read new isLeft flag directly
    final isLeft = (data['isLeft'] as bool?) ?? false;
    final crossAlign = isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    // title/desc
    final title = data['name'] as String? ?? '';
    final desc = data['description'] as String? ?? '';
    // products URLs
    final ids = data['products'] as List<dynamic>? ?? [];
    // Sort the products by their indices if an index field exists in the database
    final prodSnaps = await FirebaseFirestore.instance
      .collection('products')
      .where(FieldPath.documentId, whereIn: ids)
      .get();

    final List<Map<String, dynamic>> sortedProducts = prodSnaps.docs.map((doc) {
      final data = doc.data();
      return {
        'index': data['index'] ?? 0, // Default to 0 if index is missing
        'imgPath': data['imgPath'],
      };
    }).toList()
      ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

    final List<String> productUrls = [];
    for (var product in sortedProducts) {
      final String? path = product['imgPath'];
      if (path != null) {
        final url = await storage.refFromURL(path).getDownloadURL();
        productUrls.add(url);
      }
    }

    // Add debugging logs to verify the order of productUrls
    print('Sorted product URLs: $productUrls');
    // price
    final price = data['price'] as int?;
    return SlideData(
      backgroundUrl: bgUrl,
      overlayColor: Colors.black.withOpacity(opacity),
      title: title,
      desc: desc,
      isLeft: isLeft,
      crossAlign: crossAlign,
      productUrls: productUrls,
      price: price, // Add price to SlideData
    );
  }));
}

class ProductCarouselPage extends StatelessWidget {
  const ProductCarouselPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
      .collection('offers')
      .where('isActive', isEqualTo: true)
      .snapshots();

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(        stream: stream,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(child: Text('Greška: ${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Nema ponuda'));
          }

          return FutureBuilder<List<SlideData>>(
            future: _fetchSlideData(docs),
            builder: (fCtx, fSnap) {
              if (fSnap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final slides = fSnap.data ?? [];
              return CarouselSlider(
                items: slides.map((slide) {
                  return SizedBox.expand(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Stack(fit: StackFit.expand, children: [
                        if (slide.backgroundUrl != null)
                          CachedNetworkImage(imageUrl: slide.backgroundUrl!, fit: BoxFit.cover),
                        Container(color: slide.overlayColor),
                        Padding(
                          padding: slide.isLeft
                            ? const EdgeInsets.symmetric(horizontal: 150)
                            : const EdgeInsets.symmetric(horizontal: 180), // Increased by 20%
                          child: Row(
                            mainAxisAlignment: slide.isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: slide.isLeft
                              ? [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: slide.crossAlign,
                                        children: [
                                          Text(slide.title, style: const TextStyle(color: Colors.white, fontSize: 70, fontWeight: FontWeight.bold), textAlign: slide.isLeft ? TextAlign.left : TextAlign.right),
                                          const SizedBox(height: 8),
                                          Text(slide.desc, style: const TextStyle(color: Colors.white70, fontSize: 40), textAlign: slide.isLeft ? TextAlign.left : TextAlign.right),
                                          const SizedBox(height: 16),
                                          if (slide.price != null)
                                            Text('Cijena: ${slide.price}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: slide.productUrls.length > 1 ? 850.0 : 800.0,
                                    height: 700.0,
                                    child: Stack(
                                      children: slide.productUrls.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final url = entry.value;
                                        // If only one product, always show red centered container
                                        if (slide.productUrls.length == 1) {
                                          return Center(
                                            child: CachedNetworkImage(imageUrl: url, width: 800, height: 800, fit: BoxFit.contain),
                                          );
                                        } else if (index == 0) {
                                          return Positioned(
                                            bottom: 0,
                                            right: -70,
                                            child: CachedNetworkImage(imageUrl: url, width: 500, height: 500, fit: BoxFit.contain),
                                          );
                                        } else if (index == 1) {
                                          return Center(
                                            child: CachedNetworkImage(imageUrl: url, width: 800, height: 800, fit: BoxFit.contain),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      }).toList().reversed.toList(),
                                    ),
                                  ),
                                ]
                              : [
                                  SizedBox(
                                    width: slide.productUrls.length > 1 ? 850.0 : 800.0,
                                    height: 700.0,
                                    child: Stack(
                                      children: slide.productUrls.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final url = entry.value;
                                        // If only one product, always show red centered container
                                        if (slide.productUrls.length == 1) {
                                          return Center(
                                            child: CachedNetworkImage(imageUrl: url, width: 800, height: 800, fit: BoxFit.contain),
                                          );
                                        } else if (index == 0) {
                                          return Positioned(
                                            bottom: 0,
                                            left: -70,
                                            child: CachedNetworkImage(imageUrl: url, width: 500, height: 500, fit: BoxFit.contain),
                                          );
                                        } else if (index == 1) {
                                          return Center(
                                            child: CachedNetworkImage(imageUrl: url, width: 800, height: 800, fit: BoxFit.contain),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      }).toList().reversed.toList(),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: slide.crossAlign,
                                        children: [
                                          Text(slide.title, style: const TextStyle(color: Colors.white, fontSize: 70, fontWeight: FontWeight.bold), textAlign: slide.isLeft ? TextAlign.left : TextAlign.right),
                                          const SizedBox(height: 8),
                                          Text(slide.desc, style: const TextStyle(color: Colors.white70, fontSize: 40), textAlign: slide.isLeft ? TextAlign.left : TextAlign.right),
                                          const SizedBox(height: 16),
                                          if (slide.price != null)
                                            Text('Cijena: ${slide.price}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                          ),
                        ),
                      ]),
                    ),
                  );
                }).toList(),
                options: CarouselOptions(height: MediaQuery.of(context).size.height, viewportFraction: 1.0, enlargeCenterPage: false, autoPlay: true),
              );
            },
          );
        },
      ),
    );
  }
}

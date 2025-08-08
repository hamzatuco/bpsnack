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
  List<SlideData> slides = [];
  for (var snapDoc in docs) {
    try {
      final data = snapDoc.data() as Map<String, dynamic>;
      print('Offer doc: ${snapDoc.id}, data: $data');

      // background downloadURL
      String? bgUrl;
      if (data['backgroundImagePath'] != null && data['backgroundImagePath'] is String && (data['backgroundImagePath'] as String).isNotEmpty) {
        try {
          bgUrl = await storage.refFromURL(data['backgroundImagePath'] as String).getDownloadURL();
        } catch (e) {
          print('Greška kod backgroundImagePath za offer ${snapDoc.id}: $e');
        }
      } else {
        print('Offer ${snapDoc.id} nema validan backgroundImagePath');
      }

      // overlay opacity
      final opacity = (data['opacity'] as num? ?? 0).toDouble().clamp(0, 100) / 100;
      // read new isLeft flag directly
      final isLeft = (data['isLeft'] as bool?) ?? false;
      final crossAlign = isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end;
      // title/desc
      final title = data['name'] as String? ?? '';
      final desc = data['description'] as String? ?? '';

      // products URLs
      final ids = (data['products'] as List<dynamic>? ?? []).whereType<String>().toList();
      if (ids.isEmpty) {
        print('Offer ${snapDoc.id} nema proizvode (products) ili je prazno.');
      }

      List<Map<String, dynamic>> sortedProducts = [];
      if (ids.isNotEmpty) {
        try {
          final prodSnaps = await FirebaseFirestore.instance
              .collection('products')
              .where(FieldPath.documentId, whereIn: ids)
              .get();
          sortedProducts = prodSnaps.docs.map((doc) {
            final pdata = doc.data();
            return {
              'index': pdata['index'] ?? 0,
              'imgPath': pdata['imgPath'],
            };
          }).toList()
            ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
        } catch (e) {
          print('Greška kod učitavanja products za offer ${snapDoc.id}: $e');
        }
      }

      final List<String> productUrls = [];
      for (var product in sortedProducts) {
        final String? path = product['imgPath'];
        if (path != null && path.isNotEmpty) {
          try {
            final url = await storage.refFromURL(path).getDownloadURL();
            productUrls.add(url);
          } catch (e) {
            print('Greška kod imgPath za product: $path, error: $e');
          }
        } else {
          print('Product nema validan imgPath: $product');
        }
      }
      print('Offer ${snapDoc.id} - sorted product URLs: $productUrls');

      // price
      final price = data['price'] as int?;

      slides.add(SlideData(
        backgroundUrl: bgUrl,
        overlayColor: Colors.black.withOpacity(opacity),
        title: title,
        desc: desc,
        isLeft: isLeft,
        crossAlign: crossAlign,
        productUrls: productUrls,
        price: price,
      ));
    } catch (e) {
      print('Greška kod obrade offer dokumenta: $e');
    }
  }
  print('Ukupno uspešno kreiranih SlideData: ${slides.length}');
  return slides;
}

class ProductCarouselPage extends StatelessWidget {
  const ProductCarouselPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
      .collection('offers')
      .where('isActive', isEqualTo: true)
      .snapshots();
    // Debug: Prikaz poruke kada se build pokrene
    print('ProductCarouselPage build() pokrenut - čekam podatke iz Firestore offers kolekcije');

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (ctx, snap) {
          if (snap.hasError) {
            print('Firestore error: \\${snap.error}');
            return Center(child: Text('Greška: ���${snap.error}'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            print('Firestore offers loading...');
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          print('Firestore offers loaded: broj dokumenata = \\${docs.length}');
          if (docs.isEmpty) {
            print('Nema ponuda u Firestore-u');
            return const Center(child: Text('Nema ponuda'));
          }

          return FutureBuilder<List<SlideData>>(
            future: _fetchSlideData(docs),
            builder: (fCtx, fSnap) {
              if (fSnap.connectionState != ConnectionState.done) {
                print('Učitavanje slajdova (SlideData) iz Firestore-a...');
                return const Center(child: CircularProgressIndicator());
              }
              final slides = fSnap.data ?? [];
              print('Broj učitanih SlideData: \\${slides.length}');
              for (var slide in slides) {
                print('SlideData: title=\\${slide.title}, desc=\\${slide.desc}, price=\\${slide.price}, productUrls=\\${slide.productUrls.length}');
              }
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

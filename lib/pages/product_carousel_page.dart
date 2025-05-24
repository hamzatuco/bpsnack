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
  SlideData({
    required this.backgroundUrl,
    required this.overlayColor,
    required this.title,
    required this.desc,
    required this.isLeft,
    required this.crossAlign,
    required this.productUrls,
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
    final prodSnaps = await FirebaseFirestore.instance
      .collection('products')
      .where(FieldPath.documentId, whereIn: ids)
      .get();
    final List<String> productUrls = [];
    for (var p in prodSnaps.docs) {
      final prodData = p.data() as Map<String, dynamic>;
      final String? path = prodData['imgPath'];
      if (path != null) {
        final url = await storage.refFromURL(path).getDownloadURL();
        productUrls.add(url);
      }
    }
    return SlideData(
      backgroundUrl: bgUrl,
      overlayColor: Colors.black.withOpacity(opacity),
      title: title,
      desc: desc,
      isLeft: isLeft,
      crossAlign: crossAlign,
      productUrls: productUrls,
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
                        Align(
                          alignment: slide.isLeft ? Alignment.bottomLeft : Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: slide.crossAlign, children: [
                              Text(slide.title, style: const TextStyle(color: Colors.white, fontSize: 100, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(slide.desc, style: const TextStyle(color: Colors.white70, fontSize: 40)),
                            ]),
                          ),
                        ),
                        //////////////////////////SLIKE//////////////////////////
                        Padding(
                          padding: slide.isLeft
                            ? const EdgeInsets.only(right: 150)
                            : const EdgeInsets.only(left: 150),
                          child: Align(
                            alignment: slide.isLeft ? Alignment.centerRight : Alignment.centerLeft,
                            child: SizedBox(
                              width: slide.productUrls.length > 1 ? 700.0 + 80.0 : 700.0,
                              height: 700.0,
                              child: Stack(
                                children: slide.productUrls.asMap().entries.map((entry) {
                                  final url = entry.value;
                                  return Center(
                                    child: CachedNetworkImage(
                                      imageUrl: url,
                                      width: 800.0,
                                      height: 800.0,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
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

import 'package:go_router/go_router.dart';

import '../../domain/product.dart';
import '../../routing/router.dart';
import 'product_detail_screen.dart';

/// Sub-routes of `/produk`, drawn full screen over the tab bar.
final productRoutes = <RouteBase>[
  GoRoute(
    path: ':id',
    parentNavigatorKey: rootKey,
    builder: (_, s) {
      final p = s.extra;
      return ProductDetailScreen(id: int.parse(s.pathParameters['id']!), initial: p is Product ? p : null);
    },
  ),
];

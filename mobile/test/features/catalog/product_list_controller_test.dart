import 'package:dokani/core/network/api_exception.dart';
import 'package:dokani/features/catalog/application/catalog_providers.dart';
import 'package:dokani/features/catalog/data/catalog_repository.dart';
import 'package:dokani/features/catalog/data/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/catalog_fakes.dart';

void main() {
  (ProviderContainer, FakeCatalogRepository) setup({int pageSize = 30, int count = 5}) {
    final repository = FakeCatalogRepository(
      pageSize: pageSize,
      products: [
        for (var i = 1; i <= count; i++)
          makeProduct(
            id: i,
            name: 'Item ${i.toString().padLeft(2, '0')}',
            variants: [makeVariant(id: i * 100, status: i == 1 ? StockStatus.out : (i == 2 ? StockStatus.low : StockStatus.inStock))],
          ),
      ],
    );
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.listen(productListProvider, (_, _) {});
    return (container, repository);
  }

  test('opening loads the first page', () async {
    final (container, _) = setup();

    await container.read(productListProvider.notifier).open();

    final state = container.read(productListProvider);
    expect(state.items, hasLength(5));
    expect(state.loading, isFalse);
    expect(state.hasMore, isFalse);
  });

  test('search and stock filter narrow the list and reset paging', () async {
    final (container, _) = setup();
    final controller = container.read(productListProvider.notifier);
    await controller.open();

    await controller.search('  item 03 ');
    expect(container.read(productListProvider).items.map((p) => p.name), ['Item 03']);
    expect(container.read(productListProvider).isFiltered, isTrue);

    await controller.search('');
    await controller.filterByStock(StockFilter.low);
    expect(container.read(productListProvider).items.map((p) => p.name), ['Item 02']);

    await controller.filterByStock(StockFilter.out);
    expect(container.read(productListProvider).items.map((p) => p.name), ['Item 01']);
  });

  test('loadMore appends pages until there are no more', () async {
    final (container, repository) = setup(pageSize: 2, count: 5);
    final controller = container.read(productListProvider.notifier);
    await controller.open();
    expect(container.read(productListProvider).items, hasLength(2));
    expect(container.read(productListProvider).hasMore, isTrue);

    await controller.loadMore();
    await controller.loadMore();
    expect(container.read(productListProvider).items.map((p) => p.id), [1, 2, 3, 4, 5]);
    expect(container.read(productListProvider).hasMore, isFalse);

    final calls = repository.queries.length;
    await controller.loadMore();
    expect(repository.queries.length, calls, reason: 'No request once the last page is loaded.');
  });

  test('a failure keeps what is already shown and can be retried', () async {
    final (container, repository) = setup(pageSize: 2);
    final controller = container.read(productListProvider.notifier);
    await controller.open();

    repository.failNext = const ApiException(kind: ApiErrorKind.network);
    await controller.loadMore();

    var state = container.read(productListProvider);
    expect(state.items, hasLength(2));
    expect(state.error, isA<ApiException>());

    await controller.loadMore();
    state = container.read(productListProvider);
    expect(state.items, hasLength(4));
    expect(state.error, isNull);
  });

  test('a slow answer to an old search does not overwrite the newer one', () async {
    final (container, _) = setup();
    final controller = container.read(productListProvider.notifier);

    // Two searches started back to back: only the second may win.
    final first = controller.search('item 01');
    final second = controller.search('item 05');
    await Future.wait([first, second]);

    expect(container.read(productListProvider).items.map((p) => p.name), ['Item 05']);
    expect(container.read(productListProvider).query, 'item 05');
  });
}

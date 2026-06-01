import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/article.dart';
import '../../../services/backend_service.dart';

class ArticlesNotifier extends StateNotifier<List<Article>> {
  final BackendService _backendService;

  ArticlesNotifier(this._backendService) : super([]);

  Future<void> fetchArticles() async {
    try {
      final data = await _backendService.getArticles();
      if (!mounted) return;
      final articles = (data['articles'] as List<dynamic>? ?? [])
          .map((a) => Article.fromJson(Map<String, dynamic>.from(a as Map)))
          .toList();
      state = articles;
    } catch (e) {
      debugPrint('ArticlesNotifier.fetchArticles error: $e');
      if (mounted) state = [];
    }
  }

  Future<void> markArticleRead(String articleId) async {
    try {
      await _backendService.markArticleRead(articleId);
      try { await _backendService.completeQuest('read_article'); } catch (_) {}
    } catch (e) {
      debugPrint('ArticlesNotifier.markArticleRead error: $e');
    }

    if (!mounted) return;
    state = state.map((article) {
      if (article.id == articleId) {
        return article.copyWith(isRead: true);
      }
      return article;
    }).toList();
  }

  int get readCount => state.where((a) => a.isRead).length;
  int get totalPoints => state.fold(0, (sum, a) => sum + (a.isRead ? a.points : 0));
}

final backendServiceArticlesProvider = Provider((ref) => BackendService());

final articlesProvider = StateNotifierProvider<ArticlesNotifier, List<Article>>((ref) {
  final backendService = ref.watch(backendServiceArticlesProvider);
  return ArticlesNotifier(backendService);
});

final readArticlesProvider = Provider<int>((ref) {
  final articles = ref.watch(articlesProvider);
  return articles.where((a) => a.isRead).length;
});

final articlePointsProvider = Provider<int>((ref) {
  final articles = ref.watch(articlesProvider);
  return articles.fold(0, (sum, a) => sum + (a.isRead ? a.points : 0));
});

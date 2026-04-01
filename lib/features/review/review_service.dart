import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_review/in_app_review.dart';

import '../settings/data/settings_repository.dart';
import 'review_dialog.dart';

/// Manages in-app review prompts at expense count milestones.
///
/// Flow:
/// 1. Custom "Loving Enough Spent?" dialog (styled to app)
/// 2a. Happy path: native OS review sheet via in_app_review
/// 2b. Unhappy path: feedback email bottom sheet
///
/// The native review sheet appearance is fully controlled by the OS —
/// no custom styling is possible. [requestReview] silently no-ops if
/// Google's quota is exceeded; this is expected and not an error.
class ReviewService {
  /// Expense count milestones at which to show the review prompt.
  static const List<int> milestones = [5, 25, 100];

  static const String _playStoreId = 'com.stegodonsoftware.enoughspent';

  final SettingsRepository _repository;

  ReviewService(this._repository);

  int get _lastCompleted => _repository.getLastReviewedMilestone();

  /// Returns the lowest milestone not yet completed, or null if all done.
  int? _nextMilestone() {
    for (final m in milestones) {
      if (m > _lastCompleted) return m;
    }
    return null;
  }

  /// Check if a review prompt should be shown and show it if so.
  ///
  /// Call this after saving an expense. [totalExpenses] is the new total count.
  Future<void> maybePromptReview(BuildContext context, int totalExpenses) async {
    final next = _nextMilestone();
    if (next == null || totalExpenses < next) return;
    if (!context.mounted) return;

    final isHappy = await showReviewPromptDialog(context, next);

    if (isHappy == true) {
      // Happy — mark all milestones done so we never prompt again
      _repository.setLastReviewedMilestone(milestones.last);
      if (kDebugMode) {
        debugPrint('ReviewService: would trigger native review (milestone $next)');
        return;
      }
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      } else {
        await review.openStoreListing(appStoreId: _playStoreId);
      }
    } else {
      // Not happy or dismissed — advance past this milestone, try again at the next
      _repository.setLastReviewedMilestone(next);
      if (isHappy == false && context.mounted) await showFeedbackSheet(context);
    }
  }
}

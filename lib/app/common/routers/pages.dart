import 'package:get/get.dart';
import 'package:xuanyu/app/bootstrap/root_shell_page.dart';
import 'package:xuanyu/app/common/routers/names.dart';
import 'package:xuanyu/app/pages/home/today_fortune/view.dart';
import 'package:xuanyu/app/pages/home/today_health/view.dart';
import 'package:xuanyu/app/pages/home/destiny_match/view.dart';
import 'package:xuanyu/app/pages/main/view.dart';
import 'package:xuanyu/app/pages/system/forget_password/view.dart';
import 'package:xuanyu/app/pages/system/login/view.dart';
import 'package:xuanyu/app/pages/system/profile_setup/view.dart';
import 'package:xuanyu/app/pages/system/register/view.dart';
import 'package:xuanyu/app/pages/voice/voice_match/view.dart';
import 'package:xuanyu/app/pages/home/bazi/view.dart';
import 'package:xuanyu/app/pages/home/today_merit/view.dart';
import 'package:xuanyu/features/role_diagnosis/role_diagnosis_input_page.dart';
import 'package:xuanyu/features/message/master_consult_entry_page.dart';
import 'package:xuanyu/features/wish/wish_prayer_page.dart';
import 'package:xuanyu/features/shop/shop_page.dart';
import 'package:xuanyu/features/shop/goodwill_echo_page.dart';
import 'package:xuanyu/features/fortune/ziwei/ziwei_input_page.dart';
import 'package:xuanyu/features/fortune/astrology/astrology_page.dart';
import 'package:xuanyu/features/fortune/qizheng/qizheng_page.dart';
import 'package:xuanyu/features/fortune/partner_portrait/partner_portrait_page.dart';
import 'package:xuanyu/features/zodiac/zodiac_page.dart';
import 'package:xuanyu/features/suggestions/suggestion_submit_page.dart';
import 'package:xuanyu/features/community/team_home_page.dart';

class RoutePages {
  RoutePages._();

  static final List<GetPage<dynamic>> list = <GetPage<dynamic>>[
    GetPage<dynamic>(name: RouteNames.root, page: () => const RootShellPage()),
    GetPage<dynamic>(
      name: RouteNames.systemLogin,
      page: () => const ShellLoginPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.systemRegister,
      page: () => const ShellRegisterPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.systemForgetPassword,
      page: () => const ShellForgetPasswordPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.systemProfileSetup,
      page: () => const ShellProfileSetupPage(),
    ),
    GetPage<dynamic>(name: RouteNames.main, page: () => const ShellMainPage()),
    GetPage<dynamic>(
      name: RouteNames.homeTodayFortune,
      page: () => const TodayFortunePage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeTodayMerit,
      page: () => const TodayMeritPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeWishPrayer,
      page: () => const WishPrayerPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.roleDiagnosis,
      page: () => const RoleDiagnosisInputPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeBazi,
      page: () => const BaziPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeZiwei,
      page: () => const ZiweiInputPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeAstrology,
      page: () => const AstrologyEntryPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeQizheng,
      page: () => const QizhengEntryPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeTodayHealth,
      page: () => const TodayHealthPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeMasterConsult,
      page: () => const MasterConsultEntryPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.homeDestinyMatch,
      page: () => const DestinyMatchPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.voiceMatch,
      page: () => const VoiceMatchPage(),
    ),
    GetPage<dynamic>(name: RouteNames.shop, page: () => const ShopPage()),
    GetPage<dynamic>(
      name: RouteNames.goodwillEcho,
      page: () => const GoodwillEchoPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.partnerPortrait,
      page: () => const PartnerPortraitPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.suggestions,
      page: () => const SuggestionSubmitPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.zodiac,
      page: () => const ZodiacPage(),
    ),
    GetPage<dynamic>(
      name: RouteNames.teamHome,
      page: () {
        final raw = Get.arguments;
        final args =
            raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        return TeamHomePage(
          conversationId: (args['conversationId'] as num?)?.toInt() ?? 0,
          initialName: args['name']?.toString() ?? '部落',
          initialTitle: args['title']?.toString(),
          initialMemberCount: (args['memberCount'] as num?)?.toInt(),
          initialMaxMembers: (args['maxMembers'] as num?)?.toInt(),
        );
      },
    ),
  ];
}

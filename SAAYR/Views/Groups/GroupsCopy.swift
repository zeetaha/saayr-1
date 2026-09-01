//
//  GroupsCopy.swift
//  SAAYR
//
//  Every string the Groups flow shows, in both languages. `Translations`
//  already carries five `groups.*` keys, but the flow needs closer to a
//  hundred; keeping them here rather than swelling the global table means the
//  whole feature — copy included — stays in one folder.
//

import Foundation

struct GroupsCopy {

    let isEnglish: Bool

    private func t(_ english: String, _ arabic: String) -> String {
        isEnglish ? english : arabic
    }

    // MARK: List

    var title: String          { t("Groups", "المجموعات") }
    var myGroups: String       { t("My Groups", "مجموعاتي") }
    var discover: String       { t("Discover", "اكتشف") }
    var searchGroups: String   { t("Search groups by name…", "ابحث عن مجموعة بالاسم…") }
    var sortNote: String       { t("Sorted by most active in the last 7 days", "مرتبة حسب الأكثر نشاطًا خلال 7 أيام") }
    var createNew: String      { t("Create a new group", "إنشاء مجموعة جديدة") }
    var noResults: String      { t("No group with that name\nTry another name or create your own",
                                   "لا توجد مجموعة بهذا الاسم\nجرّب اسمًا آخر أو أنشئ مجموعتك") }
    var noGroupsYet: String    { t("You're not in a group yet\nJoin one from Discover or create your own",
                                   "لست في أي مجموعة بعد\nانضم من اكتشف أو أنشئ مجموعتك") }

    var publicBadge: String    { t("🌍 Public", "🌍 عامة") }
    var privateBadge: String   { t("🔒 Private", "🔒 خاصة") }
    var youAreAdmin: String    { t("You're the admin", "أنت المشرف") }
    var thisWeek: String       { t("THIS WEEK", "هذا الأسبوع") }

    func members(_ count: Int) -> String {
        t("\(count) members", "\(count) أعضاء")
    }

    /// "14th" / "3rd" — the rank pill on a group card.
    func ordinal(_ value: Int) -> String {
        guard isEnglish else { return "\(value)" }
        let tens = value % 100
        if (11...13).contains(tens) { return "\(value)th" }
        switch value % 10 {
        case 1:  return "\(value)st"
        case 2:  return "\(value)nd"
        case 3:  return "\(value)rd"
        default: return "\(value)th"
        }
    }

    // MARK: Group

    var feed: String        { t("Feed", "النشاط") }
    var leaderboard: String { t("Leaderboard", "المتصدرون") }
    var preview: String     { t("Preview", "معاينة") }
    var requestToJoin: String { t("Request to join", "طلب الانضمام") }
    var requestPending: String { t("⏳ Request pending", "⏳ الطلب قيد المراجعة") }
    var previewLocked: String { t("The feed and leaderboard unlock\nonce your request is approved",
                                  "يفتح النشاط والمتصدرون\nبمجرد الموافقة على طلبك") }
    var reportGroup: String  { t("🚩 Report this group", "🚩 الإبلاغ عن المجموعة") }
    var leaveGroup: String   { t("Leave group", "مغادرة المجموعة") }
    var feedNote: String     { t("You see activity from your join date · we keep the last 30 days",
                                 "ترى النشاط من تاريخ انضمامك · نحتفظ بآخر 30 يومًا") }
    var emptyFeed: String    { t("Nothing here yet\nThe first check-in shows up the moment it happens",
                                 "لا يوجد نشاط بعد\nأول تسجيل حضور سيظهر فور حدوثه") }
    var resetStrip: String   { t("Resets Sunday · 6 days left", "يُعاد الأحد · باقي 6 أيام") }
    var boardNote: String    { t("This rank lives inside the group only — zero effect on your main rank",
                                 "هذا الترتيب داخل المجموعة فقط — لا يؤثر على ترتيبك العام") }
    var points: String       { t("pts", "نقطة") }

    func level(_ value: Int) -> String { t("L\(value)", "م\(value)") }

    // MARK: Create

    var newGroup: String       { t("New group", "مجموعة جديدة") }
    var groupName: String      { t("Group name", "اسم المجموعة") }
    var groupNameHint: String  { t("e.g. Hittin Crew", "مثال: شلة حطين") }
    var shortDescription: String { t("Short description — optional", "وصف مختصر — اختياري") }
    var descriptionHint: String { t("What do you do together?", "ماذا تفعلون معًا؟") }
    var cover: String          { t("Cover", "الغلاف") }
    var visibility: String     { t("Visibility", "الظهور") }
    var publicOption: String   { t("🌍 Public", "🌍 عامة") }
    var privateOption: String  { t("🔒 Private", "🔒 خاصة") }
    var publicHelp: String     { t("Anyone can find it in Discover and request to join — you approve.",
                                   "يمكن لأي شخص إيجادها في اكتشف وطلب الانضمام — وأنت توافق.") }
    var privateHelp: String    { t("Hidden from Discover — you invite members yourself by username or link.",
                                   "مخفية عن اكتشف — تدعو الأعضاء بنفسك باسم المستخدم أو برابط.") }
    var createGroup: String    { t("Create group", "إنشاء المجموعة") }

    // MARK: Admin

    var groupAdmin: String     { t("Group admin", "إدارة المجموعة") }
    var editGroup: String      { t("Edit group", "تعديل المجموعة") }
    var editGroupSub: String   { t("Name · description · cover · visibility", "الاسم · الوصف · الغلاف · الظهور") }
    var inviteMembers: String  { t("Invite members", "دعوة أعضاء") }
    var inviteMembersSub: String { t("By username or a single-use link", "باسم المستخدم أو برابط لمرة واحدة") }
    var joinRequests: String   { t("Join requests", "طلبات الانضمام") }
    var joinRequestsSub: String { t("Approve or decline", "الموافقة أو الرفض") }
    var dangerZone: String     { t("Danger zone", "منطقة الخطر") }
    var disbandGroup: String   { t("Disband group", "حل المجموعة") }
    var adminNote: String      { t("The admin cannot leave — disband, or admin auto-transfers to the most active member if the account is deleted",
                                   "لا يمكن للمشرف المغادرة — إما الحل، أو تنتقل الإدارة تلقائيًا لأنشط عضو عند حذف الحساب") }
    var remove: String         { t("Remove", "إزالة") }
    var approve: String        { t("Approve", "موافقة") }
    var decline: String        { t("Decline", "رفض") }
    var noRequests: String     { t("No new requests", "لا توجد طلبات جديدة") }
    var requestsNote: String   { t("Declined players can re-request after 7 days · if the group goes private, pending requests stay in your queue",
                                   "يمكن للمرفوضين إعادة الطلب بعد 7 أيام · وإذا أصبحت المجموعة خاصة تبقى الطلبات المعلّقة في قائمتك") }

    func membersSection(_ count: Int) -> String {
        t("Members · \(count)", "الأعضاء · \(count)")
    }

    // MARK: Invite

    var inviteSub: String      { t("Search a username, or share a link.", "ابحث عن اسم مستخدم، أو شارك رابطًا.") }
    var searchUsername: String { t("Search by username…", "ابحث باسم المستخدم…") }
    var orByLink: String       { t("OR BY LINK", "أو برابط") }
    var copy: String           { t("Copy", "نسخ") }
    var invite: String         { t("Invite", "دعوة") }
    var sent: String           { t("Sent ✓", "أُرسلت ✓") }
    var noPlayer: String       { t("No player with that username", "لا يوجد لاعب بهذا الاسم") }
    var inviteLinkNote: String { t("One person per link · expires in 48 hours · opening it joins instantly",
                                   "شخص واحد لكل رابط · ينتهي خلال 48 ساعة · فتحه ينضم فورًا") }
    var generateNewLink: String { t("Generate new link", "إنشاء رابط جديد") }

    // MARK: Report & disband

    var reportTitle: String    { t("Report this group", "الإبلاغ عن المجموعة") }
    var reportSub: String      { t("Your report goes to the Saayr team and is reviewed privately.",
                                   "يصل بلاغك إلى فريق سعير ويُراجع بسرية.") }
    var reasonName: String     { t("Inappropriate name", "اسم غير لائق") }
    var reasonPhoto: String    { t("Inappropriate photo", "صورة غير لائقة") }
    var reasonOther: String    { t("Something else", "شيء آخر") }
    var sendReport: String     { t("Send report", "إرسال البلاغ") }
    var cancel: String         { t("Cancel", "إلغاء") }
    var yesDisband: String     { t("Yes, disband it", "نعم، احذفها") }

    func disbandTitle(_ name: String) -> String {
        t("Disband \(name)?", "حل \(name)؟")
    }

    func disbandSub(_ count: Int) -> String {
        t("This is final — all \(count) members are notified instantly and the group disappears.",
          "هذا القرار نهائي — يُبلَّغ الأعضاء الـ\(count) فورًا وتختفي المجموعة.")
    }

    // MARK: Toasts

    var toastRequestSent: String { t("Request sent — the admin will get back to you",
                                     "أُرسل الطلب — سيرد عليك المشرف") }
    var toastLinkCopied: String  { t("Link copied ✓", "نُسخ الرابط ✓") }
    var toastNewLink: String     { t("New link ready — the old one is now invalid",
                                     "رابط جديد جاهز — القديم لم يعد صالحًا") }
    var toastInvited: String     { t("They got an invite notification", "وصلهم إشعار الدعوة") }
    var toastReported: String    { t("Report received ✓ — the Saayr team will review it",
                                     "استلمنا البلاغ ✓ — سيراجعه فريق سعير") }
    var toastDisbanded: String   { t("Group disbanded 💔", "حُلّت المجموعة 💔") }
    var toastEditPending: String { t("Editing a group needs the server — coming with the API",
                                     "تعديل المجموعة يحتاج الخادم — قادم مع الواجهة البرمجية") }

    func toastCreated(_ name: String) -> String {
        t("Created \"\(name)\" 🎉 — invite your first member",
          "أُنشئت \"\(name)\" 🎉 — ادعُ أول عضو")
    }

    func toastLeft(_ name: String) -> String {
        t("You left \(name)", "غادرت \(name)")
    }

    func toastRemoved(_ name: String) -> String {
        t("\(name) removed — they got an in-app notification",
          "أُزيل \(name) — وصله إشعار داخل التطبيق")
    }

    func toastApproved(_ name: String) -> String {
        t("\(name) joined the group 👋", "انضم \(name) إلى المجموعة 👋")
    }

    func toastDeclined(_ name: String) -> String {
        t("\(name) declined — they can re-request in 7 days",
          "رُفض \(name) — يمكنه إعادة الطلب بعد 7 أيام")
    }
}

// MARK: - Server-backed copy
//
// Added when the screens stopped running on seeded data: states that only
// exist once there is a network in the way, and the phrases that wrap a value
// the server sends.

extension GroupsCopy {

    var loading: String   { isEnglish ? "Loading…" : "جارٍ التحميل…" }
    var retry: String     { isEnglish ? "Try again" : "أعد المحاولة" }
    var offline: String   { isEnglish ? "Couldn't reach the server\nPull down to try again"
                                     : "تعذّر الوصول إلى الخادم\nاسحب للأسفل لإعادة المحاولة" }
    var saveChanges: String { isEnglish ? "Save changes" : "حفظ التغييرات" }
    var somethingWentWrong: String { isEnglish ? "Something went wrong. Try again."
                                               : "حدث خطأ ما. حاول مرة أخرى." }
    var toastSaved: String { isEnglish ? "Saved ✓" : "تم الحفظ ✓" }
    var noMembers: String { isEnglish ? "No members listed yet" : "لا يوجد أعضاء بعد" }
    var activeToday: String { isEnglish ? "active today" : "نشط اليوم" }

    /// "active 1h ago" — the relative part comes from Foundation, localised.
    func active(_ relative: String) -> String {
        isEnglish ? "active \(relative)" : "نشطة \(relative)"
    }

    func joined(_ day: String) -> String {
        isEnglish ? "Joined \(day)" : "انضم في \(day)"
    }

    func requested(_ relative: String) -> String {
        isEnglish ? "requested \(relative)" : "طلب \(relative)"
    }

    /// The leaderboard reset strip. The server sends the instant; the count of
    /// days is worked out here.
    func resetsIn(_ days: Int) -> String {
        if days <= 0 { return isEnglish ? "Resets today" : "يُعاد اليوم" }
        if days == 1 { return isEnglish ? "Resets tomorrow · 1 day left" : "يُعاد غدًا · باقي يوم واحد" }
        return isEnglish ? "Resets in \(days) days" : "يُعاد خلال \(days) أيام"
    }

    func expires(_ relative: String) -> String {
        isEnglish ? "Link expires \(relative)" : "ينتهي الرابط \(relative)"
    }
}

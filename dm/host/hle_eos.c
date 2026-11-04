// Epic Online Services, offline, for a game that does not expect it to fail (profile key eos_offline). The host never loads the SDK's NRO (hle_ro.c), and the EOS_* imports are named stubs that return 0,
// which is EOS_Success for the calls that return a result. Absolum checks the null platform and plays offline. Shredder's Revenge does not: its C# wrapper turns the null handle into a null object and
// calls a method on it (main+0x75a890, a null read at +0x10). With the key, the platform and its interfaces are handles that exist, opaque to the game; no operation completes, so no login ever succeeds.
#include "hle.h"

static uint8_t g_eos_platform;
#define EOS_INTERFACE(name) HLE("EOS_Platform_Get" #name "Interface", void *, h_eos_get_##name, void *platform) { return platform; }
HLE("EOS_Platform_Create", void *, h_eos_platform_create, const void *options) {
    (void)options;
    if (!DM_GAME_EOS_OFFLINE) return NULL;
    LOG("EOS_Platform_Create: an offline platform (the SDK is not loaded); no EOS operation completes");
    return &g_eos_platform;
}
EOS_INTERFACE(Achievements) EOS_INTERFACE(AntiCheatClient) EOS_INTERFACE(AntiCheatServer) EOS_INTERFACE(Auth) EOS_INTERFACE(Connect) EOS_INTERFACE(CustomInvites) EOS_INTERFACE(Ecom)
EOS_INTERFACE(Friends) EOS_INTERFACE(KWS) EOS_INTERFACE(Leaderboards) EOS_INTERFACE(Lobby) EOS_INTERFACE(Metrics) EOS_INTERFACE(Mods) EOS_INTERFACE(P2P) EOS_INTERFACE(PlayerDataStorage)
EOS_INTERFACE(Presence) EOS_INTERFACE(ProgressionSnapshot) EOS_INTERFACE(RTC) EOS_INTERFACE(RTCAdmin) EOS_INTERFACE(Reports) EOS_INTERFACE(Sanctions) EOS_INTERFACE(Sessions) EOS_INTERFACE(Stats)
EOS_INTERFACE(TitleStorage) EOS_INTERFACE(UI) EOS_INTERFACE(UserInfo)

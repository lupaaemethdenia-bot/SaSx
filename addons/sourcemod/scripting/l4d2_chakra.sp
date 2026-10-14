#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "include/chakra_core.inc"
#undef REQUIRE_PLUGIN
#include "include/l4d_CreateSurvivorBot.inc"
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION "0.2.0"
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define CHARACTER_COUNT 8
#define SIM_TICK 0.05
#define POOL_TICK 0.25
#define EFFECT_FLIGHT "fire_small_01"
#define EFFECT_IMPACT "molotov_explosion"

public Plugin myinfo = {
    name = "L4D2 Chakra: Techniques", author = "SaSx contributors",
    description = "Fixed random loadouts, illusion clone, great fire and budgeted Rasengan",
    version = PLUGIN_VERSION, url = "https://github.com/lupaaemethdenia-bot/SaSx"
};
static const char g_Names[CHAKRA_TECHNIQUES][] = {
    "Огненный шар", "Иллюзорный клон", "Великое огненное уничтожение", "Расенган"
};
// These states belong to survivor characters, not network connection slots.
ChakraPool g_Pool[CHARACTER_COUNT];
TechniqueLoadout g_Loadout[CHARACTER_COUNT];
float g_ReadyAt[CHARACTER_COUNT][CHAKRA_TECHNIQUES];
int g_Selected[CHARACTER_COUNT];
int g_Character[MAXPLAYERS + 1];
bool g_Control[MAXPLAYERS + 1], g_AttackWasDown[MAXPLAYERS + 1], g_RasenganHeld[MAXPLAYERS + 1];
bool g_Casting[MAXPLAYERS + 1];
int g_CastTech[MAXPLAYERS + 1];
float g_CastFinish[MAXPLAYERS + 1], g_NextHud[MAXPLAYERS + 1];
ArrayList g_Effects;
bool g_RoundActive;
float g_LastPoolTick;

bool g_Flying[MAXPLAYERS + 1];
float g_Position[MAXPLAYERS + 1][3], g_Direction[MAXPLAYERS + 1][3];
float g_Distance[MAXPLAYERS + 1], g_FlightAt[MAXPLAYERS + 1];
int g_EffectRef[MAXPLAYERS + 1];
bool g_GreatFire[MAXPLAYERS + 1];
float g_FireNextTick[MAXPLAYERS + 1];
DamageWindow g_FireWindow[MAXPLAYERS + 1];
ArrayList g_FireCarry[MAXPLAYERS + 1];
int g_FireEffects[MAXPLAYERS + 1][5];
bool g_Rasengan[MAXPLAYERS + 1];
RasenganBudget g_RasBudget[MAXPLAYERS + 1];
float g_RasLastTick[MAXPLAYERS + 1], g_RasFraction[MAXPLAYERS + 1], g_RasNextEffect[MAXPLAYERS + 1];
float g_RasRate[MAXPLAYERS + 1];
int g_CloneUserId[MAXPLAYERS + 1];
float g_CloneEnds[MAXPLAYERS + 1];
bool g_IsClone[MAXPLAYERS + 1];
bool g_RejectCloneTakeover[MAXPLAYERS + 1];
float g_CloneOrigin[MAXPLAYERS + 1][3], g_CloneAngles[MAXPLAYERS + 1][3];

ConVar g_Enabled, g_Maximum, g_Cost[CHAKRA_TECHNIQUES], g_Regen, g_RegenDelay, g_CastTime, g_Cooldown;
ConVar g_Speed, g_Range, g_Radius, g_Damage, g_TankScale;
ConVar g_FireDuration, g_FireMultiplier, g_FireRange, g_FireHalfAngle;
ConVar g_RasDuration, g_RasLimit, g_RasTankTime, g_RasReach, g_RasSplashRange, g_RasSplashScale;
ConVar g_CloneDuration, g_DevMode;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax) {
    MarkNativeAsOptional("CreateSurvivorBot");
    return APLRes_Success;
}

public void OnPluginStart() {
    if (GetEngineVersion() != Engine_Left4Dead2) SetFailState("This plugin requires Left 4 Dead 2.");
    g_Effects = new ArrayList();
    g_Enabled = CreateConVar("sm_chakra_enabled", "1", "Enable techniques.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_Maximum = CreateConVar("sm_chakra_max", "100", "Maximum chakra.", FCVAR_NONE, true, 1.0, true, 10000.0);
    g_Cost[JUTSU_FIREBALL] = CreateConVar("sm_chakra_fireball_cost", "25", "Fireball cost.", FCVAR_NONE, true, 1.0, true, 10000.0);
    g_Cost[JUTSU_CLONE] = CreateConVar("sm_chakra_clone_cost", "20", "Illusion clone cost.", FCVAR_NONE, true, 1.0, true, 10000.0);
    g_Cost[JUTSU_GREATFIRE] = CreateConVar("sm_chakra_greatfire_cost", "45", "Great fire cost.", FCVAR_NONE, true, 1.0, true, 10000.0);
    g_Cost[JUTSU_RASENGAN] = CreateConVar("sm_chakra_rasengan_cost", "80", "Rasengan activation cost.", FCVAR_NONE, true, 1.0, true, 10000.0);
    g_Regen = CreateConVar("sm_chakra_regen", "1", "Chakra recovered per second.", FCVAR_NONE, true, 0.0, true, 1000.0);
    g_RegenDelay = CreateConVar("sm_chakra_regen_delay", "5", "Regeneration delay after starting a cast.", FCVAR_NONE, true, 0.0, true, 120.0);
    g_CastTime = CreateConVar("sm_chakra_cast_time", "0.85", "Preparation time; hand-seal animations are a later stage.", FCVAR_NONE, true, 0.1, true, 10.0);
    g_Cooldown = CreateConVar("sm_chakra_cooldown", "2.5", "Cooldown after release, per technique.", FCVAR_NONE, true, 0.1, true, 60.0);
    g_Speed = CreateConVar("sm_chakra_fireball_speed", "1100", "Fireball speed.", FCVAR_NONE, true, 100.0, true, 5000.0);
    g_Range = CreateConVar("sm_chakra_fireball_range", "1800", "Fireball maximum travel.", FCVAR_NONE, true, 100.0, true, 10000.0);
    g_Radius = CreateConVar("sm_chakra_fireball_radius", "500", "Fireball blast radius.", FCVAR_NONE, true, 50.0, true, 1500.0);
    g_Damage = CreateConVar("sm_chakra_fireball_damage", "300", "Fireball center damage.", FCVAR_NONE, true, 1.0, true, 5000.0);
    g_TankScale = CreateConVar("sm_chakra_tank_scale", "0.25", "Tank multiplier for fireball and great fire ONLY.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_FireDuration = CreateConVar("sm_chakra_greatfire_duration", "3", "Great fire duration.", FCVAR_NONE, true, 0.1, true, 10.0);
    g_FireMultiplier = CreateConVar("sm_chakra_greatfire_multiplier", "1.5", "Full exposure damage relative to fireball center.", FCVAR_NONE, true, 0.1, true, 10.0);
    g_FireRange = CreateConVar("sm_chakra_greatfire_range", "900", "Great fire forward range.", FCVAR_NONE, true, 100.0, true, 2000.0);
    g_FireHalfAngle = CreateConVar("sm_chakra_greatfire_half_angle", "65", "Great fire half angle; 65 means a 130 degree cone.", FCVAR_NONE, true, 10.0, true, 85.0);
    g_RasDuration = CreateConVar("sm_chakra_rasengan_duration", "10", "Rasengan active duration after preparation.", FCVAR_NONE, true, 0.1, true, 60.0);
    g_RasLimit = CreateConVar("sm_chakra_rasengan_limit", "4000", "Shared damage threshold; a final ordinary kill can cross it.", FCVAR_NONE, true, 1.0, true, 20000.0);
    g_RasTankTime = CreateConVar("sm_chakra_rasengan_tank_time", "1.5", "Continuous solo target contact needed to deliver the budget.", FCVAR_NONE, true, 0.1, true, 10.0);
    g_RasReach = CreateConVar("sm_chakra_rasengan_reach", "125", "Rasengan melee reach.", FCVAR_NONE, true, 40.0, true, 250.0);
    g_RasSplashRange = CreateConVar("sm_chakra_rasengan_splash_range", "72", "Range for at most two secondary victims.", FCVAR_NONE, true, 0.0, true, 150.0);
    g_RasSplashScale = CreateConVar("sm_chakra_rasengan_splash_scale", "0.25", "Secondary special infected damage multiplier.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_CloneDuration = CreateConVar("sm_chakra_clone_duration", "12", "Illusion lifetime; dissipates on first hit or pin.", FCVAR_NONE, true, 1.0, true, 30.0);
    g_DevMode = CreateConVar("sm_chakra_dev_mode", "0", "Allow root admins to test unassigned techniques. Keep 0 for normal play.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_Enabled.AddChangeHook(EnabledChanged);
    RegConsoleCmd("sm_jutsu", CommandCast, "Activate the selected technique.");
    RegConsoleCmd("sm_jutsu1", CommandSelect1, "Select technique slot 1.");
    RegConsoleCmd("sm_jutsu2", CommandSelect2, "Select technique slot 2.");
    RegConsoleCmd("sm_jutsu3", CommandSelect3, "Select technique slot 3.");
    RegConsoleCmd("sm_chakra", CommandStatus, "Show chakra and fixed loadout.");
    RegConsoleCmd("sm_jutsuoff", CommandWeapons, "Use ordinary weapons for comparison.");
    RegAdminCmd("sm_jutsutest", CommandTest, ADMFLAG_ROOT, "Test fireball, clone, greatfire or rasengan without changing loadout.");
    HookEvent("round_start", EventRoundStart);
    HookEvent("round_end", EventRoundEnd);
    HookEvent("mission_lost", EventRoundEnd);
    HookEvent("map_transition", EventRoundEnd);
    HookEvent("finale_win", EventRoundEnd);
    HookEvent("player_spawn", EventPlayerSpawn);
    HookEvent("player_death", EventPlayerInterrupted);
    HookEvent("player_team", EventPlayerInterrupted);
    HookEvent("player_incapacitated", EventPlayerInterrupted);
    HookEvent("player_bot_replace", EventReplacement);
    HookEvent("bot_player_replace", EventReplacement);
    AutoExecConfig(true, "l4d2_chakra");
    for (int client = 1; client <= MaxClients; client++) InitializeClient(client);
    BeginRound(true);
    CreateTimer(SIM_TICK, TimerSimulation, _, TIMER_REPEAT);
    CreateTimer(POOL_TICK, TimerPools, _, TIMER_REPEAT);
}

public void OnMapStart() {
    PrecacheEffect(EFFECT_FLIGHT);
    PrecacheEffect(EFFECT_IMPACT);
    PrecacheEffect("impact_steam");
    BeginRound(true);
}
public void OnMapEnd() { StopRound(); }
public void OnPluginEnd() { StopRound(); delete g_Effects; }
public void OnClientPutInServer(int client) { InitializeClient(client); }
public void OnClientDisconnect(int client) {
    CancelClient(client);
    g_Character[client] = -1;
    g_IsClone[client] = false;
    g_RejectCloneTakeover[client] = false;
}
void InitializeClient(int client) {
    CancelClient(client);
    g_Character[client] = -1;
    g_Control[client] = true;
    g_AttackWasDown[client] = false;
    g_NextHud[client] = 0.0;
    g_EffectRef[client] = INVALID_ENT_REFERENCE;
    g_IsClone[client] = false;
    g_RejectCloneTakeover[client] = false;
}
void BeginRound(bool newMap) {
    StopRound();
    for (int character = 0; character < CHARACTER_COUNT; character++) {
        g_Pool[character].Reset(g_Maximum.FloatValue);
        if (newMap) { g_Loadout[character].Clear(); g_Selected[character] = 0; }
        for (int technique = 0; technique < CHAKRA_TECHNIQUES; technique++) g_ReadyAt[character][technique] = 0.0;
    }
    for (int client = 1; client <= MaxClients; client++) {
        g_Character[client] = -1;
        g_Control[client] = true;
        g_AttackWasDown[client] = false;
        g_NextHud[client] = 0.0;
    }
    g_RoundActive = true;
    g_LastPoolTick = GetGameTime();
}
void StopRound() {
    g_RoundActive = false;
    for (int client = 1; client <= MaxClients; client++) CancelClient(client);
    RemoveAllEffects();
}
public void EnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (!convar.BoolValue) {
        for (int client = 1; client <= MaxClients; client++) CancelClient(client);
        RemoveAllEffects();
    }
}
public void EventRoundStart(Event event, const char[] name, bool dontBroadcast) { BeginRound(false); }
public void EventRoundEnd(Event event, const char[] name, bool dontBroadcast) { StopRound(); }
public void EventPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && !g_IsClone[client]) { CancelClient(client); g_Character[client] = -1; }
}
public void EventPlayerInterrupted(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && !g_IsClone[client]) CancelClient(client);
}
public void EventReplacement(Event event, const char[] name, bool dontBroadcast) {
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));
    if (player > 0 && g_RejectCloneTakeover[player] && StrEqual(name, "player_bot_replace")) {
        // The engine may create a replacement bot when returning the player
        // to spectators. It must not leave a second, unowned illusion behind.
        g_RejectCloneTakeover[player] = false;
        if (bot > 0) {
            g_IsClone[bot] = true; g_Character[bot] = -1;
            RequestFrame(KickCloneActor, GetClientUserId(bot));
        }
        return;
    }
    int cloneOwner = FindCloneOwner(event.GetInt("bot"));
    if (cloneOwner > 0 || (bot > 0 && g_IsClone[bot])) {
        if (StrEqual(name, "bot_player_replace") && player > 0) {
            if (cloneOwner > 0) g_CloneUserId[cloneOwner] = 0;
            // Wait for the engine's own takeover operation to finish before
            // changing teams; never kick a human client.
            g_RejectCloneTakeover[player] = true;
            RequestFrame(RejectCloneControl, GetClientUserId(player));
            if (bot > 0) RequestFrame(KickCloneActor, GetClientUserId(bot));
        }
        return;
    }
    if (player <= 0 || bot <= 0) return;
    CancelClient(player); CancelClient(bot);
    g_Character[player] = -1; g_Character[bot] = -1;
}
bool EnsureCharacter(int client) {
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR || g_IsClone[client]) return false;
    int character = GetEntProp(client, Prop_Send, "m_survivorCharacter");
    if (character < 0 || character >= CHARACTER_COUNT) return false;
    if (g_Character[client] != character) { CancelClient(client); g_Character[client] = character; }
    if (!g_Loadout[character].assigned) g_Loadout[character].Assign(GetRandomInt(0, 23));
    return true;
}
bool CanUseTechnique(int client) {
    if (!g_RoundActive || !g_Enabled.BoolValue || client <= 0 || client > MaxClients || !IsClientInGame(client)
        || g_IsClone[client] || GetClientTeam(client) != TEAM_SURVIVOR || !IsPlayerAlive(client)) return false;
    if (GetEntProp(client, Prop_Send, "m_isIncapacitated") || GetEntProp(client, Prop_Send, "m_isHangingFromLedge")) return false;
    static const char useProps[][] = {"m_useActionTarget", "m_useActionOwner"};
    for (int i = 0; i < sizeof(useProps); i++)
        if (HasEntProp(client, Prop_Send, useProps[i]) && GetEntPropEnt(client, Prop_Send, useProps[i]) > 0) return false;
    return !IsPinned(client);
}
bool IsPinned(int client) {
    static const char props[][] = {"m_tongueOwner", "m_pounceAttacker", "m_jockeyAttacker", "m_carryAttacker", "m_pummelAttacker"};
    for (int i = 0; i < sizeof(props); i++) {
        int attacker = GetEntPropEnt(client, Prop_Send, props[i]);
        if (attacker > 0 && IsValidEntity(attacker)) return true;
    }
    return false;
}
bool IsBusy(int client) { return g_Casting[client] || g_Flying[client] || g_GreatFire[client] || g_Rasengan[client]; }
bool HoldingSupportItem(int client) {
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon)) return false;
    char name[48]; GetEntityClassname(weapon, name, sizeof(name));
    return StrEqual(name, "weapon_first_aid_kit") || StrEqual(name, "weapon_defibrillator")
        || StrEqual(name, "weapon_pain_pills") || StrEqual(name, "weapon_adrenaline")
        || StrEqual(name, "weapon_upgradepack_explosive") || StrEqual(name, "weapon_upgradepack_incendiary");
}
void Tell(int client, const char[] format, any ...) {
    char message[256]; VFormat(message, sizeof(message), format, 3);
    if (client > 0 && IsClientInGame(client)) {
        PrintToChat(client, "[Чакра] %s", message);
        PrintToConsole(client, "[Chakra] %s", message);
    } else PrintToServer("[Chakra] %s", message);
}
public Action CommandCast(int client, int args) {
    if (EnsureCharacter(client)) {
        g_Control[client] = true;
        int character = g_Character[client];
        RequestCast(client, g_Loadout[character].slots[g_Selected[character]]);
    } else Tell(client, "Команда требует игрового выжившего. Введи !jutsu в игровой чат.");
    return Plugin_Handled;
}
public Action CommandSelect1(int client, int args) { return SelectTechnique(client, 0); }
public Action CommandSelect2(int client, int args) { return SelectTechnique(client, 1); }
public Action CommandSelect3(int client, int args) { return SelectTechnique(client, 2); }
Action SelectTechnique(int client, int slot) {
    if (!EnsureCharacter(client)) { Tell(client, "Выбор техники доступен выжившему в игровом чате."); return Plugin_Handled; }
    if (IsBusy(client)) { Tell(client, "Сначала дождись окончания текущей техники."); return Plugin_Handled; }
    if (slot < 0 || slot >= CHAKRA_SLOTS) return Plugin_Handled;
    int character = g_Character[client];
    g_Selected[character] = slot; g_Control[client] = true; g_NextHud[client] = 0.0;
    int technique = g_Loadout[character].slots[slot];
    Tell(client, "Ячейка %d: %s (%.0f чакры).", slot + 1, g_Names[technique], g_Cost[technique].FloatValue);
    return Plugin_Handled;
}
public Action CommandWeapons(int client, int args) {
    if (client > 0 && IsClientInGame(client)) {
        CancelClient(client); g_Control[client] = false;
        Tell(client, "Включено обычное оружие. Выбери ячейку техники, чтобы вернуться к техникам.");
    }
    return Plugin_Handled;
}
public Action CommandStatus(int client, int args) {
    if (!EnsureCharacter(client)) { Tell(client, "Нет игрового персонажа. Введи !chakra в игровой чат."); return Plugin_Handled; }
    int character = g_Character[client];
    Tell(client, "%.0f / %.0f | Версия %s", g_Pool[character].amount, g_Maximum.FloatValue, PLUGIN_VERSION);
    for (int slot = 0; slot < CHAKRA_SLOTS; slot++) {
        int technique = g_Loadout[character].slots[slot];
        Tell(client, "%s%d: %s — %.0f чакры", slot == g_Selected[character] ? "> " : "", slot + 1, g_Names[technique], g_Cost[technique].FloatValue);
    }
    if (g_Rasengan[client]) Tell(client, "Расенган: осталось %.0f урона и %.1f сек.", g_RasBudget[client].remaining, g_RasBudget[client].ends - GetGameTime());
    return Plugin_Handled;
}
public Action CommandTest(int client, int args) {
    if (!g_DevMode.BoolValue) {
        Tell(client, "Тестовый режим выключен. Администратор может включить sm_chakra_dev_mode 1 для проверки техник.");
        return Plugin_Handled;
    }
    char name[32]; GetCmdArg(1, name, sizeof(name));
    int technique = -1;
    if (StrEqual(name, "fireball", false)) technique = JUTSU_FIREBALL;
    else if (StrEqual(name, "clone", false)) technique = JUTSU_CLONE;
    else if (StrEqual(name, "greatfire", false)) technique = JUTSU_GREATFIRE;
    else if (StrEqual(name, "rasengan", false)) technique = JUTSU_RASENGAN;
    if (technique == -1) Tell(client, "Тест администратора: !jutsutest fireball|clone|greatfire|rasengan. Набор не меняется.");
    else if (EnsureCharacter(client)) { g_Control[client] = true; RequestCast(client, technique); }
    return Plugin_Handled;
}
void RequestCast(int client, int technique) {
    if (!CanUseTechnique(client)) { Tell(client, "Техника недоступна: выживший должен быть живым, свободным и не обездвиженным."); return; }
    if (!EnsureCharacter(client) || IsBusy(client)) { Tell(client, "Предыдущая техника ещё выполняется."); return; }
    if (technique == JUTSU_CLONE && !CloneCanStart(client)) return;
    int character = g_Character[client]; float now = GetGameTime();
    if (now < g_ReadyAt[character][technique]) { Tell(client, "Перезарядка: %.1f сек.", g_ReadyAt[character][technique] - now); return; }
    g_Pool[character].SetMaximum(g_Maximum.FloatValue);
    if (!g_Pool[character].Reserve(g_Cost[technique].FloatValue, now, g_RegenDelay.FloatValue)) {
        Tell(client, "Недостаточно чакры: %.0f / %.0f.", g_Pool[character].amount, g_Cost[technique].FloatValue); return;
    }
    g_Casting[client] = true; g_CastTech[client] = technique;
    g_CastFinish[client] = now + g_CastTime.FloatValue; g_NextHud[client] = 0.0;
    Tell(client, "%s: подготовка.", g_Names[technique]);
}
void ReleaseCast(int client, float now) {
    int technique = g_CastTech[client], character = g_Character[client];
    g_Casting[client] = false;
    if (technique == JUTSU_CLONE && !DeployClone(client, now)) { g_Pool[character].Cancel(); return; }
    g_Pool[character].Commit();
    g_ReadyAt[character][technique] = now + g_Cooldown.FloatValue;
    switch (technique) {
        case JUTSU_FIREBALL: ReleaseFireball(client, now);
        case JUTSU_GREATFIRE: BeginGreatFire(client, now);
        case JUTSU_RASENGAN: BeginRasengan(client, now);
    }
}
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3],
    int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
    if (g_IsClone[client]) { buttons = 0; impulse = 0; weapon = 0; vel[0] = vel[1] = vel[2] = 0.0; return Plugin_Changed; }
    bool attack = (buttons & IN_ATTACK) != 0;
    bool rising = attack && !g_AttackWasDown[client];
    g_AttackWasDown[client] = attack; g_RasenganHeld[client] = attack;
    if (IsFakeClient(client) || !g_Control[client] || !CanUseTechnique(client)) return Plugin_Continue;
    // Slots 4/5 are still vanilla at this stage; allow healing and pills.
    if (!IsBusy(client) && HoldingSupportItem(client)) return Plugin_Continue;
    int original = buttons; buttons &= ~IN_ATTACK;
    if (g_Casting[client] || g_GreatFire[client] || g_Rasengan[client]) buttons &= ~(IN_ATTACK2 | IN_RELOAD | IN_USE);
    if (rising && !IsBusy(client) && EnsureCharacter(client)) {
        int character = g_Character[client]; RequestCast(client, g_Loadout[character].slots[g_Selected[character]]);
    }
    return original != buttons ? Plugin_Changed : Plugin_Continue;
}
public Action TimerPools(Handle timer) {
    float now = GetGameTime(), elapsed = now - g_LastPoolTick; g_LastPoolTick = now;
    if (!g_RoundActive || !g_Enabled.BoolValue) return Plugin_Continue;
    bool visited[CHARACTER_COUNT];
    for (int client = 1; client <= MaxClients; client++) {
        if (!EnsureCharacter(client) || !IsPlayerAlive(client)) continue;
        int character = g_Character[client]; g_Pool[character].SetMaximum(g_Maximum.FloatValue);
        if (!visited[character] && CanUseTechnique(client) && !g_GreatFire[client] && !g_Rasengan[client])
            g_Pool[character].Regenerate(elapsed, now, g_Regen.FloatValue);
        visited[character] = true;
        if (!IsFakeClient(client) && now >= g_NextHud[client]) {
            int technique = g_Loadout[character].slots[g_Selected[character]];
            if (g_Rasengan[client])
                PrintHintText(client, "Чакра: %.0f / %.0f\nРасенган: %.1f сек. | %.0f урона осталось\nУдерживай ЛКМ рядом с целью", g_Pool[character].amount, g_Maximum.FloatValue, g_RasBudget[client].ends - now, g_RasBudget[client].remaining);
            else PrintHintText(client, "Чакра: %.0f / %.0f\n[%d] %s — %.0f чакры\n%s", g_Pool[character].amount, g_Maximum.FloatValue,
                g_Selected[character] + 1, g_Names[technique], g_Cost[technique].FloatValue,
                g_Casting[client] ? "Подготовка…" : (g_GreatFire[client] ? "Огонь активен" : (g_Control[client] ? "ЛКМ / V — применить" : "Режим обычного оружия")));
            g_NextHud[client] = now + 1.0;
        }
    }
    UpdateClones(now);
    return Plugin_Continue;
}
public Action TimerSimulation(Handle timer) {
    if (!g_RoundActive || !g_Enabled.BoolValue) return Plugin_Continue;
    float now = GetGameTime();
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsBusy(client)) continue;
        if (!CanUseTechnique(client)) { CancelClient(client); continue; }
        if (g_Casting[client] && now >= g_CastFinish[client]) ReleaseCast(client, now);
        if (g_Flying[client]) MoveFireball(client, now);
        if (g_GreatFire[client]) TickGreatFire(client, now);
        if (g_Rasengan[client]) TickRasengan(client, now);
    }
    return Plugin_Continue;
}
void CancelClient(int client) {
    int character = g_Character[client];
    if (g_Casting[client] && character >= 0 && character < CHARACTER_COUNT) g_Pool[character].Cancel();
    g_Casting[client] = false; g_Flying[client] = false; g_Rasengan[client] = false; g_RasenganHeld[client] = false;
    RemoveEffect(g_EffectRef[client]); g_EffectRef[client] = INVALID_ENT_REFERENCE;
    StopGreatFire(client); RemoveClone(client);
}
bool IsZombie(int entity) {
    if (entity <= 0 || !IsValidEntity(entity)) return false;
    if (entity <= MaxClients) return IsClientInGame(entity) && GetClientTeam(entity) == TEAM_INFECTED && IsPlayerAlive(entity);
    char classname[32]; GetEntityClassname(entity, classname, sizeof(classname));
    return (StrEqual(classname, "infected") || StrEqual(classname, "witch")) && GetEntProp(entity, Prop_Data, "m_iHealth") > 0;
}
bool IsCommon(int entity) {
    if (entity <= MaxClients || !IsValidEntity(entity)) return false;
    char classname[32]; GetEntityClassname(entity, classname, sizeof(classname));
    return StrEqual(classname, "infected");
}
int ZombieHealth(int entity) { return GetEntProp(entity, Prop_Data, "m_iHealth"); }
void ZombieCenter(int entity, float center[3]) { GetEntPropVector(entity, Prop_Send, "m_vecOrigin", center); center[2] += 36.0; }
float FireDamageScale(int entity) {
    return entity <= MaxClients && GetEntProp(entity, Prop_Send, "m_zombieClass") == 8 ? g_TankScale.FloatValue : 1.0;
}
void CollectZombies(ArrayList victims) {
    for (int client = 1; client <= MaxClients; client++) if (IsZombie(client)) victims.Push(EntIndexToEntRef(client));
    static const char classes[][] = {"infected", "witch"};
    for (int type = 0; type < sizeof(classes); type++) {
        int entity = -1;
        while ((entity = FindEntityByClassname(entity, classes[type])) != -1)
            if (IsZombie(entity)) victims.Push(EntIndexToEntRef(entity));
    }
}
bool VisibleBetween(const float from[3], const float to[3], int target) {
    Handle trace = TR_TraceRayFilterEx(from, to, MASK_SHOT, RayType_EndPoint, TraceBlast, target);
    bool blocked = TR_StartSolid(trace) || (TR_DidHit(trace) && TR_GetEntityIndex(trace) != target);
    delete trace; return !blocked;
}
public bool TraceBlast(int entity, int contentsMask, any target) {
    if (entity == target || entity == 0) return true;
    if (entity > 0 && entity <= MaxClients) return false;
    if (IsValidEntity(entity)) {
        char classname[32]; GetEntityClassname(entity, classname, sizeof(classname));
        if (StrEqual(classname, "infected") || StrEqual(classname, "witch")) return false;
    }
    return true;
}
public bool TraceProjectile(int entity, int contentsMask) {
    return !(entity > 0 && entity <= MaxClients && IsClientInGame(entity) && GetClientTeam(entity) == TEAM_SURVIVOR);
}
void RemoveEffect(int reference) {
    if (g_Effects == null) return;
    int index = g_Effects.FindValue(reference); if (index == -1) return;
    g_Effects.Erase(index);
    int entity = EntRefToEntIndex(reference);
    if (entity != INVALID_ENT_REFERENCE && entity > MaxClients && IsValidEntity(entity)) RemoveEntity(entity);
}
void RemoveAllEffects() {
    if (g_Effects == null) return;
    while (g_Effects.Length > 0) RemoveEffect(g_Effects.Get(g_Effects.Length - 1));
}
void PrecacheEffect(const char[] name) {
    int table = FindStringTable("ParticleEffectNames");
    if (table == INVALID_STRING_TABLE || FindStringIndex(table, name) != INVALID_STRING_INDEX) return;
    bool locked = LockStringTables(false); AddToStringTable(table, name); LockStringTables(locked);
}
int SpawnEffect(const char[] name, const float position[3], float lifetime = 0.0) {
    int entity = CreateEntityByName("info_particle_system"); if (entity == -1) return -1;
    DispatchKeyValue(entity, "effect_name", name); DispatchKeyValue(entity, "start_active", "0");
    if (!DispatchSpawn(entity)) { RemoveEntity(entity); return -1; }
    TeleportEntity(entity, position, NULL_VECTOR, NULL_VECTOR); ActivateEntity(entity); AcceptEntityInput(entity, "Start");
    int reference = EntIndexToEntRef(entity); g_Effects.Push(reference);
    if (lifetime > 0.0) CreateTimer(lifetime, TimerRemoveEffect, reference, TIMER_FLAG_NO_MAPCHANGE);
    return entity;
}
public Action TimerRemoveEffect(Handle timer, any reference) { RemoveEffect(reference); return Plugin_Stop; }

#include "jutsu/fireball.sp"
#include "jutsu/greatfire.sp"
#include "jutsu/rasengan.sp"
#include "jutsu/clone.sp"

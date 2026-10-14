#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "include/chakra_core.inc"

#define PLUGIN_VERSION "0.1.0"
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define FLIGHT_TICK 0.05
#define POOL_TICK 0.25
#define EFFECT_FLIGHT "fire_small_01"
#define EFFECT_IMPACT "molotov_explosion"

public Plugin myinfo =
{
    name = "L4D2 Chakra: Fireball Prototype",
    author = "SaSx contributors",
    description = "Chakra, slow regeneration and a castable area-of-effect fireball",
    version = PLUGIN_VERSION,
    url = ""
};

ChakraPool g_Pool[MAXPLAYERS + 1];
bool g_Casting[MAXPLAYERS + 1];
bool g_Flying[MAXPLAYERS + 1];
float g_CastFinish[MAXPLAYERS + 1];
float g_ReadyAt[MAXPLAYERS + 1];
float g_Position[MAXPLAYERS + 1][3];
float g_Direction[MAXPLAYERS + 1][3];
float g_Distance[MAXPLAYERS + 1];
float g_NextHud[MAXPLAYERS + 1];
float g_FlightAt[MAXPLAYERS + 1];
int g_EffectRef[MAXPLAYERS + 1];
ArrayList g_Effects;
bool g_RoundActive;
float g_LastPoolTick;

ConVar g_Enabled;
ConVar g_Maximum;
ConVar g_Cost;
ConVar g_Regen;
ConVar g_RegenDelay;
ConVar g_CastTime;
ConVar g_Cooldown;
ConVar g_Speed;
ConVar g_Range;
ConVar g_Radius;
ConVar g_Damage;
ConVar g_TankScale;

public void OnPluginStart()
{
    if (GetEngineVersion() != Engine_Left4Dead2)
        SetFailState("This plugin requires Left 4 Dead 2.");
    g_Effects = new ArrayList();

    g_Enabled = CreateConVar("sm_chakra_enabled", "1", "Enable the prototype.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_Maximum = CreateConVar("sm_chakra_max", "100", "Maximum chakra.", FCVAR_NONE, true, 1.0, true, 10000.0);
    g_Cost = CreateConVar("sm_chakra_fireball_cost", "25", "Chakra cost per fireball.", FCVAR_NONE, true, 1.0, true, 10000.0);
    g_Regen = CreateConVar("sm_chakra_regen", "1", "Chakra recovered per second.", FCVAR_NONE, true, 0.0, true, 1000.0);
    g_RegenDelay = CreateConVar("sm_chakra_regen_delay", "5", "Regeneration delay after starting a cast.", FCVAR_NONE, true, 0.0, true, 120.0);
    g_CastTime = CreateConVar("sm_chakra_cast_time", "0.85", "Preparation time before release; gestures are not yet implemented.", FCVAR_NONE, true, 0.1, true, 10.0);
    g_Cooldown = CreateConVar("sm_chakra_cooldown", "2.5", "Cooldown after release.", FCVAR_NONE, true, 0.1, true, 60.0);
    g_Speed = CreateConVar("sm_chakra_fireball_speed", "1100", "Projectile speed in Source units per second.", FCVAR_NONE, true, 100.0, true, 5000.0);
    g_Range = CreateConVar("sm_chakra_fireball_range", "1800", "Maximum projectile travel before exploding.", FCVAR_NONE, true, 100.0, true, 10000.0);
    g_Radius = CreateConVar("sm_chakra_fireball_radius", "500", "Blast radius in Source units.", FCVAR_NONE, true, 50.0, true, 1500.0);
    g_Damage = CreateConVar("sm_chakra_fireball_damage", "300", "Damage at the center; 35 percent remains at the edge.", FCVAR_NONE, true, 1.0, true, 5000.0);
    g_TankScale = CreateConVar("sm_chakra_tank_scale", "0.25", "Tank damage multiplier.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_Enabled.AddChangeHook(EnabledChanged);

    RegConsoleCmd("sm_jutsu", CommandFireball, "Prepare and launch a fireball.");
    RegConsoleCmd("sm_chakra", CommandStatus, "Display current chakra and cooldown.");
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

    for (int client = 1; client <= MaxClients; client++)
        ResetClient(client);
    g_RoundActive = true; // Supports loading during an existing round.
    g_LastPoolTick = GetGameTime();
    CreateTimer(FLIGHT_TICK, TimerFlight, _, TIMER_REPEAT);
    CreateTimer(POOL_TICK, TimerPools, _, TIMER_REPEAT);
}

public void OnMapStart()
{
    PrecacheEffect(EFFECT_FLIGHT);
    PrecacheEffect(EFFECT_IMPACT);
    g_RoundActive = true;
    g_LastPoolTick = GetGameTime();
    for (int client = 1; client <= MaxClients; client++)
        ResetClient(client);
    RemoveAllEffects();
}

public void OnMapEnd()
{
    g_RoundActive = false;
    for (int client = 1; client <= MaxClients; client++)
        CancelClient(client);
    RemoveAllEffects();
}

public void OnPluginEnd()
{
    for (int client = 1; client <= MaxClients; client++)
        CancelClient(client);
    RemoveAllEffects();
    delete g_Effects;
}

public void OnClientPutInServer(int client)
{
    ResetClient(client);
}

public void OnClientDisconnect(int client)
{
    ResetClient(client);
}

public void EnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (!convar.BoolValue)
        for (int client = 1; client <= MaxClients; client++)
            CancelClient(client);
}

public void EventRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_RoundActive = true;
    g_LastPoolTick = GetGameTime();
    for (int client = 1; client <= MaxClients; client++)
        ResetClient(client);
    RemoveAllEffects();
}

public void EventRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_RoundActive = false;
    for (int client = 1; client <= MaxClients; client++)
        CancelClient(client);
    RemoveAllEffects();
}

public void EventPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
        CancelClient(client); // Respawn does not refill chakra.
}

public void EventPlayerInterrupted(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
        CancelClient(client);
}

public void EventReplacement(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));
    if (player <= 0 || bot <= 0)
        return;

    // Keep chakra and cooldown with the survivor across idle/takeover.
    CancelClient(player);
    CancelClient(bot);
    int source = StrEqual(name, "player_bot_replace") ? player : bot;
    int target = (source == player) ? bot : player;
    g_Pool[target].amount = g_Pool[source].amount;
    g_Pool[target].maximum = g_Pool[source].maximum;
    g_Pool[target].regenAfter = g_Pool[source].regenAfter;
    g_ReadyAt[target] = g_ReadyAt[source];
}

public Action CommandFireball(int client, int args)
{
    if (!CanUseTechnique(client))
    {
        if (client > 0 && IsClientInGame(client))
            ReplyToCommand(client, "[Чакра] Техника доступна живому выжившему, который не обездвижен.");
        return Plugin_Handled;
    }

    float now = GetGameTime();
    if (g_Casting[client] || g_Flying[client])
    {
        ReplyToCommand(client, "[Чакра] Предыдущая техника ещё выполняется.");
        return Plugin_Handled;
    }
    if (now < g_ReadyAt[client])
    {
        ReplyToCommand(client, "[Чакра] Перезарядка: %.1f сек.", g_ReadyAt[client] - now);
        return Plugin_Handled;
    }

    g_Pool[client].SetMaximum(g_Maximum.FloatValue);
    if (!g_Pool[client].Reserve(g_Cost.FloatValue, now, g_RegenDelay.FloatValue))
    {
        ReplyToCommand(client, "[Чакра] Недостаточно чакры: %.0f / %.0f.", g_Pool[client].amount, g_Cost.FloatValue);
        return Plugin_Handled;
    }

    g_Casting[client] = true;
    g_CastFinish[client] = now + g_CastTime.FloatValue;
    g_NextHud[client] = 0.0;
    return Plugin_Handled;
}

public Action CommandStatus(int client, int args)
{
    if (client > 0 && IsClientInGame(client))
    {
        float remaining = g_ReadyAt[client] - GetGameTime();
        if (remaining < 0.0)
            remaining = 0.0;
        ReplyToCommand(client, "[Чакра] %.0f / %.0f | Огненный шар: %.0f | Перезарядка: %.1f сек.",
            g_Pool[client].amount, g_Maximum.FloatValue, g_Cost.FloatValue, remaining);
    }
    return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3],
    int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (g_Casting[client])
    {
        int original = buttons;
        buttons &= ~(IN_ATTACK | IN_ATTACK2 | IN_RELOAD | IN_USE);
        if (buttons != original)
            return Plugin_Changed;
    }
    return Plugin_Continue;
}

public Action TimerPools(Handle timer)
{
    float now = GetGameTime();
    float elapsed = now - g_LastPoolTick;
    g_LastPoolTick = now;
    if (!g_RoundActive || !g_Enabled.BoolValue)
        return Plugin_Continue;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR || !IsPlayerAlive(client))
            continue;
        g_Pool[client].SetMaximum(g_Maximum.FloatValue);
        if (CanUseTechnique(client))
            g_Pool[client].Regenerate(elapsed, now, g_Regen.FloatValue);
        if (!IsFakeClient(client) && now >= g_NextHud[client])
        {
            if (g_Casting[client])
                PrintHintText(client, "Чакра: %.0f / %.0f\nПодготовка огненного шара…", g_Pool[client].amount, g_Maximum.FloatValue);
            else
                PrintHintText(client, "Чакра: %.0f / %.0f\nОгненный шар: %.0f чакры | sm_jutsu", g_Pool[client].amount, g_Maximum.FloatValue, g_Cost.FloatValue);
            g_NextHud[client] = now + 1.0;
        }
    }
    return Plugin_Continue;
}

public Action TimerFlight(Handle timer)
{
    if (!g_RoundActive || !g_Enabled.BoolValue)
        return Plugin_Continue;
    float now = GetGameTime();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_Casting[client] && !g_Flying[client])
            continue;
        if (!CanUseTechnique(client))
        {
            CancelClient(client);
            continue;
        }
        if (g_Casting[client] && now >= g_CastFinish[client])
            ReleaseFireball(client, now);
        if (g_Flying[client])
            MoveFireball(client, now);
    }
    return Plugin_Continue;
}

bool CanUseTechnique(int client)
{
    if (!g_RoundActive || !g_Enabled.BoolValue || client <= 0 || client > MaxClients
        || !IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR || !IsPlayerAlive(client))
        return false;
    if (GetEntProp(client, Prop_Send, "m_isIncapacitated") || GetEntProp(client, Prop_Send, "m_isHangingFromLedge"))
        return false;
    static const char pinnedProps[][] = {"m_tongueOwner", "m_pounceAttacker", "m_jockeyAttacker", "m_carryAttacker", "m_pummelAttacker"};
    for (int i = 0; i < sizeof(pinnedProps); i++)
    {
        int owner = GetEntPropEnt(client, Prop_Send, pinnedProps[i]);
        if (owner > 0 && IsValidEntity(owner))
            return false;
    }
    return true;
}

void ReleaseFireball(int client, float now)
{
    float angles[3];
    GetClientEyePosition(client, g_Position[client]);
    GetClientEyeAngles(client, angles);
    GetAngleVectors(angles, g_Direction[client], NULL_VECTOR, NULL_VECTOR);
    NormalizeVector(g_Direction[client], g_Direction[client]);
    g_Casting[client] = false;
    g_Pool[client].Commit();
    g_ReadyAt[client] = now + g_Cooldown.FloatValue;
    g_Distance[client] = 0.0;
    g_FlightAt[client] = now;
    g_Flying[client] = true;
    int effect = SpawnEffect(EFFECT_FLIGHT, g_Position[client]);
    g_EffectRef[client] = (effect == -1) ? INVALID_ENT_REFERENCE : EntIndexToEntRef(effect);
}

void MoveFireball(int client, float now)
{
    float elapsed = now - g_FlightAt[client];
    g_FlightAt[client] = now;
    float remaining = g_Range.FloatValue - g_Distance[client];
    float travel = g_Speed.FloatValue * elapsed;
    if (travel > remaining)
        travel = remaining;
    if (travel < 0.0)
        travel = 0.0;

    float next[3];
    for (int axis = 0; axis < 3; axis++)
        next[axis] = g_Position[client][axis] + g_Direction[client][axis] * travel;
    float mins[3] = {-12.0, -12.0, -12.0};
    float maxs[3] = {12.0, 12.0, 12.0};
    Handle trace = TR_TraceHullFilterEx(g_Position[client], next, mins, maxs, MASK_SHOT, TraceProjectile);
    bool hit = TR_DidHit(trace) || TR_StartSolid(trace);
    if (hit)
        TR_GetEndPosition(g_Position[client], trace);
    else
        g_Position[client] = next;
    delete trace;
    g_Distance[client] += travel;

    int effect = EntRefToEntIndex(g_EffectRef[client]);
    if (effect != INVALID_ENT_REFERENCE && IsValidEntity(effect))
        TeleportEntity(effect, g_Position[client], NULL_VECTOR, NULL_VECTOR);
    if (hit || g_Distance[client] >= g_Range.FloatValue)
        ExplodeFireball(client);
}

public bool TraceProjectile(int entity, int contentsMask)
{
    // Teammates cannot accidentally intercept the projectile.
    return !(entity > 0 && entity <= MaxClients && IsClientInGame(entity) && GetClientTeam(entity) == TEAM_SURVIVOR);
}

void ExplodeFireball(int client)
{
    g_Flying[client] = false;
    RemoveFlightEffect(client);
    int effect = SpawnEffect(EFFECT_IMPACT, g_Position[client]);
    if (effect != -1)
        CreateTimer(4.0, TimerRemoveEffect, EntIndexToEntRef(effect), TIMER_FLAG_NO_MAPCHANGE);

    for (int victim = 1; victim <= MaxClients; victim++)
    {
        if (IsClientInGame(victim) && GetClientTeam(victim) == TEAM_INFECTED && IsPlayerAlive(victim))
            DamageTarget(client, victim);
    }
    DamageClass(client, "infected");
    DamageClass(client, "witch");
}

void DamageClass(int client, const char[] classname)
{
    int entity = FindEntityByClassname(-1, classname);
    while (entity != -1)
    {
        // Damage may delete the current infected, so find the next one first.
        int next = FindEntityByClassname(entity, classname);
        DamageTarget(client, entity);
        entity = next;
    }
}

void DamageTarget(int client, int victim)
{
    if (!IsValidEntity(victim))
        return;
    float center[3];
    GetEntPropVector(victim, Prop_Send, "m_vecOrigin", center);
    center[2] += 36.0;
    float damage = ChakraBlastDamage(GetVectorDistance(g_Position[client], center), g_Radius.FloatValue, g_Damage.FloatValue);
    if (damage <= 0.0)
        return;

    // Solid world geometry blocks the blast; characters do not shield the crowd.
    Handle trace = TR_TraceRayFilterEx(g_Position[client], center, MASK_SHOT, RayType_EndPoint, TraceBlast, victim);
    bool blocked = TR_DidHit(trace) && TR_GetEntityIndex(trace) != victim;
    delete trace;
    if (blocked)
        return;
    if (victim <= MaxClients && GetEntProp(victim, Prop_Send, "m_zombieClass") == 8)
        damage *= g_TankScale.FloatValue;
    if (damage > 0.0)
        SDKHooks_TakeDamage(victim, client, client, damage, DMG_BLAST);
}

public bool TraceBlast(int entity, int contentsMask, any target)
{
    if (entity == target || entity == 0)
        return true;
    if (entity > 0 && entity <= MaxClients)
        return false;
    if (IsValidEntity(entity))
    {
        char classname[32];
        GetEntityClassname(entity, classname, sizeof(classname));
        if (StrEqual(classname, "infected") || StrEqual(classname, "witch"))
            return false;
    }
    return true;
}

void CancelClient(int client)
{
    if (g_Casting[client])
        g_Pool[client].Cancel();
    g_Casting[client] = false;
    g_Flying[client] = false;
    RemoveFlightEffect(client);
}

void ResetClient(int client)
{
    CancelClient(client);
    g_Pool[client].Reset(g_Maximum.FloatValue);
    g_ReadyAt[client] = 0.0;
    g_NextHud[client] = 0.0;
}

void RemoveFlightEffect(int client)
{
    RemoveEffect(g_EffectRef[client]);
    g_EffectRef[client] = INVALID_ENT_REFERENCE;
}

void RemoveEffect(int reference)
{
    if (g_Effects == null)
        return;
    int index = g_Effects.FindValue(reference);
    if (index == -1)
        return;
    g_Effects.Erase(index);
    int entity = EntRefToEntIndex(reference);
    if (entity != INVALID_ENT_REFERENCE && entity > MaxClients && IsValidEntity(entity))
        RemoveEntity(entity);
}

void RemoveAllEffects()
{
    if (g_Effects == null)
        return;
    while (g_Effects.Length > 0)
        RemoveEffect(g_Effects.Get(g_Effects.Length - 1));
}

void PrecacheEffect(const char[] name)
{
    int table = FindStringTable("ParticleEffectNames");
    if (table == INVALID_STRING_TABLE || FindStringIndex(table, name) != INVALID_STRING_INDEX)
        return;
    bool locked = LockStringTables(false);
    AddToStringTable(table, name);
    LockStringTables(locked);
}

int SpawnEffect(const char[] name, const float position[3])
{
    int entity = CreateEntityByName("info_particle_system");
    if (entity == -1)
        return -1;
    DispatchKeyValue(entity, "effect_name", name);
    DispatchKeyValue(entity, "start_active", "0");
    if (!DispatchSpawn(entity))
    {
        RemoveEntity(entity);
        return -1;
    }
    TeleportEntity(entity, position, NULL_VECTOR, NULL_VECTOR);
    ActivateEntity(entity);
    AcceptEntityInput(entity, "Start");
    g_Effects.Push(EntIndexToEntRef(entity));
    return entity;
}

public Action TimerRemoveEffect(Handle timer, any reference)
{
    RemoveEffect(reference);
    return Plugin_Stop;
}

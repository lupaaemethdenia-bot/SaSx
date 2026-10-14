bool CloneCanStart(int client)
{
    if (g_CloneUserId[client] != 0 && GetClientOfUserId(g_CloneUserId[client]) > 0)
    {
        Tell(client, "Твой клон ещё существует."); return false;
    }
    g_CloneUserId[client] = 0;
    if (GetFeatureStatus(FeatureType_Native, "CreateSurvivorBot") != FeatureStatus_Available)
    {
        Tell(client, "Для клона не загружен l4d_CreateSurvivorBot. Проверь sm plugins list и журналы SourceMod."); return false;
    }
    if (GetClientCount(false) >= MaxClients)
    {
        Tell(client, "Для клона нет свободного серверного слота. Чакра не потрачена."); return false;
    }
    return true;
}

bool DeployClone(int client, float now)
{
    if (!CloneCanStart(client)) return false;
    float origin[3], angles[3], direction[3], destination[3];
    GetClientAbsOrigin(client, origin);
    origin[2] += 2.0;
    GetClientEyeAngles(client, angles);
    angles[0] = angles[2] = 0.0;
    GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
    for (int axis = 0; axis < 3; axis++) destination[axis] = origin[axis] + direction[axis] * 80.0;
    float mins[3] = {-16.0, -16.0, 0.0}, maxs[3] = {16.0, 16.0, 72.0};
    Handle trace = TR_TraceHullFilterEx(origin, destination, mins, maxs, MASK_PLAYERSOLID, TraceClonePlacement);
    bool blocked = TR_StartSolid(trace);
    if (TR_DidHit(trace)) TR_GetEndPosition(destination, trace);
    delete trace;
    if (blocked || GetVectorDistance(origin, destination) < 25.0)
    {
        Tell(client, "Перед персонажем недостаточно места для клона. Чакра возвращена."); return false;
    }
    float below[3], above[3]; above = destination; above[2] += 24.0;
    below = destination; below[2] -= 100.0;
    trace = TR_TraceRayFilterEx(above, below, MASK_PLAYERSOLID, RayType_EndPoint, TraceClonePlacement);
    bool floor = TR_DidHit(trace) && !TR_StartSolid(trace);
    if (floor) TR_GetEndPosition(destination, trace);
    delete trace;
    if (!floor) { Tell(client, "Для клона нужна поверхность под ногами. Чакра возвращена."); return false; }
    destination[2] += 1.0;
    trace = TR_TraceHullFilterEx(destination, destination, mins, maxs, MASK_PLAYERSOLID, TraceClonePlacement);
    blocked = TR_StartSolid(trace) || TR_AllSolid(trace);
    delete trace;
    if (blocked) { Tell(client, "Место для клона перекрыто. Чакра возвращена."); return false; }

    // Real SurvivorBot actor: ordinary infected targeting, no bile, no director
    // event, no info_goal_infected_chase, no global victim override.
    int bot = CreateSurvivorBot();
    if (bot <= 0 || !IsClientInGame(bot) || !IsFakeClient(bot) || !IsPlayerAlive(bot))
    {
        if (bot > 0 && IsClientConnected(bot) && IsFakeClient(bot)) KickClientEx(bot, "Illusion spawn failed");
        Tell(client, "Игровой движок не создал клона. Чакра возвращена."); return false;
    }
    g_IsClone[bot] = true;
    g_Character[bot] = -1;
    char model[PLATFORM_MAX_PATH]; GetClientModel(client, model, sizeof(model));
    PrecacheModel(model, true); SetEntityModel(bot, model);
    SetEntProp(bot, Prop_Send, "m_survivorCharacter", GetEntProp(client, Prop_Send, "m_survivorCharacter"));
    SetEntProp(bot, Prop_Send, "m_nSkin", GetEntProp(client, Prop_Send, "m_nSkin"));
    SetEntProp(bot, Prop_Send, "m_nBody", GetEntProp(client, Prop_Send, "m_nBody"));
    SetClientName(bot, "Illusion");
    StripCloneWeapons(bot);
    SetEntityMoveType(bot, MOVETYPE_NONE);
    SetEntProp(bot, Prop_Send, "m_CollisionGroup", 2);
    SetEntProp(bot, Prop_Send, "m_nSolidType", 0);
    SetEntProp(bot, Prop_Send, "m_usSolidFlags", GetEntProp(bot, Prop_Send, "m_usSolidFlags") | 4);
    SetEntityRenderMode(bot, RENDER_TRANSCOLOR);
    SetEntityRenderColor(bot, 255, 255, 255, 150);
    SetEntityHealth(bot, 100);
    g_CloneOrigin[bot] = destination; g_CloneAngles[bot] = angles;
    TeleportEntity(bot, destination, angles, NULL_VECTOR);
    SDKHook(bot, SDKHook_OnTakeDamage, CloneTakeDamage);
    SDKHook(bot, SDKHook_PreThinkPost, CloneFreeze);
    g_CloneUserId[client] = GetClientUserId(bot);
    g_CloneEnds[client] = now + g_CloneDuration.FloatValue;
    Tell(client, "Иллюзорный клон создан на %.0f сек.", g_CloneDuration.FloatValue);
    return true;
}

public bool TraceClonePlacement(int entity, int contentsMask)
{
    if (entity > 0 && entity <= MaxClients) return false;
    if (IsCommon(entity)) return false;
    return true;
}

void StripCloneWeapons(int bot)
{
    for (int slot = 0; slot < 5; slot++)
    {
        int weapon;
        while ((weapon = GetPlayerWeaponSlot(bot, slot)) != -1)
        {
            if (!RemovePlayerItem(bot, weapon)) break;
            if (IsValidEntity(weapon)) RemoveEntity(weapon);
        }
    }
}

public void CloneFreeze(int bot)
{
    if (!g_IsClone[bot] || !IsClientInGame(bot)) return;
    float current[3]; GetClientAbsOrigin(bot, current);
    if (GetVectorDistance(current, g_CloneOrigin[bot]) > 0.1)
        TeleportEntity(bot, g_CloneOrigin[bot], g_CloneAngles[bot], NULL_VECTOR);
}

public Action CloneTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
    if (!g_IsClone[victim]) return Plugin_Continue;
    damage = 0.0;
    RequestFrame(DissipateClone, GetClientUserId(victim));
    return Plugin_Handled;
}

public void DissipateClone(any userid)
{
    for (int owner = 1; owner <= MaxClients; owner++)
        if (g_CloneUserId[owner] == userid) { RemoveClone(owner); return; }
}

void RemoveClone(int owner)
{
    int userid = g_CloneUserId[owner];
    g_CloneUserId[owner] = 0;
    if (userid == 0) return;
    int bot = GetClientOfUserId(userid);
    if (bot > 0 && IsClientConnected(bot) && g_IsClone[bot] && IsFakeClient(bot))
        KickClientEx(bot, "Illusion dissipated");
}

int FindCloneOwner(int userid)
{
    if (userid <= 0) return 0;
    for (int owner = 1; owner <= MaxClients; owner++)
        if (g_CloneUserId[owner] == userid) return owner;
    return 0;
}

public void KickCloneActor(any userid)
{
    int bot = GetClientOfUserId(userid);
    if (bot > 0 && IsClientConnected(bot) && g_IsClone[bot] && IsFakeClient(bot))
        KickClientEx(bot, "Illusion cannot be controlled");
}

public void RejectCloneControl(any userid)
{
    int player = GetClientOfUserId(userid);
    if (player <= 0 || !IsClientInGame(player) || IsFakeClient(player)) return;
    CancelClient(player);
    g_Character[player] = -1;
    ChangeClientTeam(player, 1);
    Tell(player, "Иллюзорным клоном нельзя управлять. Выбери настоящего выжившего.");
    g_RejectCloneTakeover[player] = false;
}

void UpdateClones(float now)
{
    bool realSurvivorStanding;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client) && !g_IsClone[client] && GetClientTeam(client) == TEAM_SURVIVOR && IsPlayerAlive(client)
            && !GetEntProp(client, Prop_Send, "m_isIncapacitated") && !GetEntProp(client, Prop_Send, "m_isHangingFromLedge"))
            realSurvivorStanding = true;
    for (int owner = 1; owner <= MaxClients; owner++)
    {
        if (g_CloneUserId[owner] == 0) continue;
        int bot = GetClientOfUserId(g_CloneUserId[owner]);
        if (bot == 0 || !realSurvivorStanding || now >= g_CloneEnds[owner]
            || !IsClientInGame(bot) || !IsPlayerAlive(bot) || IsPinned(bot)) RemoveClone(owner);
        else StripCloneWeapons(bot);
    }
}

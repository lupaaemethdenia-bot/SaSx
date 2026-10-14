void ReleaseFireball(int client, float now)
{
    float angles[3];
    GetClientEyePosition(client, g_Position[client]);
    GetClientEyeAngles(client, angles);
    GetAngleVectors(angles, g_Direction[client], NULL_VECTOR, NULL_VECTOR);
    NormalizeVector(g_Direction[client], g_Direction[client]);
    g_Distance[client] = 0.0;
    g_FlightAt[client] = now;
    g_Flying[client] = true;
    int effect = SpawnEffect(EFFECT_FLIGHT, g_Position[client]);
    g_EffectRef[client] = effect == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(effect);
}

void MoveFireball(int client, float now)
{
    float elapsed = now - g_FlightAt[client];
    g_FlightAt[client] = now;
    float remaining = g_Range.FloatValue - g_Distance[client];
    float travel = g_Speed.FloatValue * elapsed;
    if (travel > remaining) travel = remaining;
    if (travel < 0.0) travel = 0.0;
    float next[3];
    for (int axis = 0; axis < 3; axis++) next[axis] = g_Position[client][axis] + g_Direction[client][axis] * travel;
    float mins[3] = {-12.0, -12.0, -12.0}, maxs[3] = {12.0, 12.0, 12.0};
    Handle trace = TR_TraceHullFilterEx(g_Position[client], next, mins, maxs, MASK_SHOT, TraceProjectile);
    bool hit = TR_DidHit(trace) || TR_StartSolid(trace);
    if (hit) TR_GetEndPosition(g_Position[client], trace);
    else g_Position[client] = next;
    delete trace;
    g_Distance[client] += travel;
    int effect = EntRefToEntIndex(g_EffectRef[client]);
    if (effect != INVALID_ENT_REFERENCE && IsValidEntity(effect)) TeleportEntity(effect, g_Position[client], NULL_VECTOR, NULL_VECTOR);
    if (hit || g_Distance[client] >= g_Range.FloatValue) ExplodeFireball(client);
}

void ExplodeFireball(int client)
{
    g_Flying[client] = false;
    RemoveEffect(g_EffectRef[client]);
    g_EffectRef[client] = INVALID_ENT_REFERENCE;
    SpawnEffect(EFFECT_IMPACT, g_Position[client], 4.0);
    ArrayList victims = new ArrayList();
    CollectZombies(victims);
    for (int i = 0; i < victims.Length; i++)
    {
        int victim = EntRefToEntIndex(victims.Get(i));
        if (!IsZombie(victim)) continue;
        float center[3];
        ZombieCenter(victim, center);
        float damage = ChakraBlastDamage(GetVectorDistance(g_Position[client], center), g_Radius.FloatValue, g_Damage.FloatValue);
        if (damage > 0.0 && VisibleBetween(g_Position[client], center, victim))
            SDKHooks_TakeDamage(victim, client, client, damage * FireDamageScale(victim), DMG_BLAST);
    }
    delete victims;
}

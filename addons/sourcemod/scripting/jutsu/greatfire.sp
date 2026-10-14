void BeginGreatFire(int client, float now)
{
    g_GreatFire[client] = true;
    g_FireNextTick[client] = now;
    g_FireWindow[client].Begin(now, g_FireDuration.FloatValue, g_Damage.FloatValue * g_FireMultiplier.FloatValue);
    g_FireCarry[client] = new ArrayList(2);
    float origin[3];
    GetClientEyePosition(client, origin);
    for (int i = 0; i < 5; i++)
    {
        int effect = SpawnEffect(EFFECT_FLIGHT, origin);
        g_FireEffects[client][i] = effect == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(effect);
    }
}

void TickGreatFire(int client, float now)
{
    if (now < g_FireNextTick[client] && now < g_FireWindow[client].ends) return;
    g_FireNextTick[client] = now + 0.1;
    float damageSlice = g_FireWindow[client].NextSlice(now);
    float origin[3], angles[3], direction[3];
    GetClientEyePosition(client, origin);
    GetClientEyeAngles(client, angles);
    GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
    NormalizeVector(direction, direction);
    if (damageSlice > 0.0)
    {
        ArrayList victims = new ArrayList();
        CollectZombies(victims);
        float minimumDot = Cosine(DegToRad(g_FireHalfAngle.FloatValue));
        for (int i = 0; i < victims.Length; i++)
        {
            int reference = victims.Get(i), victim = EntRefToEntIndex(reference);
            if (!IsZombie(victim)) continue;
            float center[3], delta[3];
            ZombieCenter(victim, center);
            MakeVectorFromPoints(origin, center, delta);
            float distance = NormalizeVector(delta, delta);
            if (!ChakraInsideCone(distance, GetVectorDotProduct(direction, delta), g_FireRange.FloatValue, minimumDot)
                || !VisibleBetween(origin, center, victim)) continue;
            // Source health is integer. Carry the fractional damage so 3s of
            // contact delivers 450, instead of losing half a point every tick.
            int row = g_FireCarry[client].FindValue(reference);
            float carry;
            if (row == -1)
            {
                int entry[2]; entry[0] = reference;
                row = g_FireCarry[client].PushArray(entry, 2);
            }
            else carry = view_as<float>(g_FireCarry[client].Get(row, 1));
            int damage = ChakraWholeDamage(damageSlice * FireDamageScale(victim), carry);
            g_FireCarry[client].Set(row, view_as<int>(carry), 1);
            // Generic damage avoids an additional engine-controlled burn DOT,
            // which would invalidate the explicitly requested 150% total.
            if (damage > 0) SDKHooks_TakeDamage(victim, client, client, float(damage), DMG_GENERIC);
        }
        delete victims;
    }
    UpdateGreatFireEffects(client, origin, angles);
    if (now >= g_FireWindow[client].ends) StopGreatFire(client);
}

void UpdateGreatFireEffects(int client, const float origin[3], const float angles[3])
{
    for (int i = 0; i < 5; i++)
    {
        int entity = EntRefToEntIndex(g_FireEffects[client][i]);
        if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity)) continue;
        float rayAngles[3], direction[3], end[3];
        rayAngles = angles;
        rayAngles[1] += (float(i) / 4.0 * 2.0 - 1.0) * g_FireHalfAngle.FloatValue;
        GetAngleVectors(rayAngles, direction, NULL_VECTOR, NULL_VECTOR);
        for (int axis = 0; axis < 3; axis++) end[axis] = origin[axis] + direction[axis] * g_FireRange.FloatValue * 0.5;
        Handle trace = TR_TraceRayFilterEx(origin, end, MASK_SHOT, RayType_EndPoint, TraceBlast, -1);
        if (TR_DidHit(trace)) TR_GetEndPosition(end, trace);
        delete trace;
        TeleportEntity(entity, end, NULL_VECTOR, NULL_VECTOR);
    }
}

void StopGreatFire(int client)
{
    g_GreatFire[client] = false;
    delete g_FireCarry[client];
    for (int i = 0; i < 5; i++)
    {
        RemoveEffect(g_FireEffects[client][i]);
        g_FireEffects[client][i] = INVALID_ENT_REFERENCE;
    }
}

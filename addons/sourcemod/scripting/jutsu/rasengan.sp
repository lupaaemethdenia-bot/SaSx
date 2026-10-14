void BeginRasengan(int client, float now)
{
    g_Rasengan[client] = true;
    g_RasBudget[client].Begin(now, g_RasDuration.FloatValue, g_RasLimit.FloatValue);
    g_RasLastTick[client] = now;
    g_RasFraction[client] = 0.0;
    g_RasRate[client] = g_RasLimit.FloatValue / g_RasTankTime.FloatValue;
    g_RasNextEffect[client] = 0.0;
    Tell(client, "Расенган активен: %.0f сек. Удерживай ЛКМ в ближнем бою; лимит %.0f урона.", g_RasDuration.FloatValue, g_RasBudget[client].remaining);
}

void TickRasengan(int client, float now)
{
    float until = now < g_RasBudget[client].ends ? now : g_RasBudget[client].ends;
    float elapsed = until - g_RasLastTick[client];
    g_RasLastTick[client] = until;
    // A delayed timer may not bank a whole damage budget into one hit.
    if (elapsed > 0.1) elapsed = 0.1;
    if (elapsed > 0.0 && g_RasBudget[client].remaining > 0.0 && g_RasenganHeld[client])
    {
        float origin[3], angles[3], direction[3], end[3];
        GetClientEyePosition(client, origin);
        GetClientEyeAngles(client, angles);
        GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
        for (int axis = 0; axis < 3; axis++) end[axis] = origin[axis] + direction[axis] * g_RasReach.FloatValue;
        float mins[3] = {-20.0, -20.0, -20.0}, maxs[3] = {20.0, 20.0, 20.0};
        Handle trace = TR_TraceHullFilterEx(origin, end, mins, maxs, MASK_SHOT, TraceRasengan);
        int primary = TR_GetEntityIndex(trace);
        delete trace;
        if (IsZombie(primary))
        {
            // No contact damage may accumulate while swinging at empty space.
            int damage = ChakraWholeDamage(g_RasRate[client] * elapsed, g_RasFraction[client]);
            float center[3];
            ZombieCenter(primary, center);
            // Capture references BEFORE damage can delete the primary entity.
            int secondary[2];
            FindRasenganSecondaries(primary, origin, center, secondary);
            ApplyRasenganDamage(client, primary, float(damage));
            for (int i = 0; i < 2 && g_RasBudget[client].remaining > 0.0; i++)
            {
                int victim = EntRefToEntIndex(secondary[i]);
                if (IsZombie(victim)) ApplyRasenganDamage(client, victim, float(damage) * g_RasSplashScale.FloatValue);
            }
            if (now >= g_RasNextEffect[client])
            {
                SpawnEffect("impact_steam", center, 0.4);
                g_RasNextEffect[client] = now + 0.2;
            }
        }
        else g_RasFraction[client] = 0.0;
    }
    else g_RasFraction[client] = 0.0;
    if (!g_RasBudget[client].Active(now))
    {
        g_Rasengan[client] = false;
        Tell(client, g_RasBudget[client].remaining <= 0.0 ? "Расенган завершён: исчерпан лимит урона." : "Расенган завершён: время истекло.");
    }
}

public bool TraceRasengan(int entity, int contentsMask)
{
    if (!TraceProjectile(entity, contentsMask)) return false;
    if (entity > MaxClients && IsValidEntity(entity))
    {
        char classname[32]; GetEntityClassname(entity, classname, sizeof(classname));
        if ((StrEqual(classname, "infected") || StrEqual(classname, "witch")) && !IsZombie(entity)) return false;
    }
    return true;
}

void FindRasenganSecondaries(int primary, const float origin[3], const float center[3], int references[2])
{
    references[0] = references[1] = INVALID_ENT_REFERENCE;
    float distances[2]; distances[0] = distances[1] = g_RasSplashRange.FloatValue + 1.0;
    if (g_RasSplashRange.FloatValue <= 0.0 || g_RasSplashScale.FloatValue <= 0.0) return;
    ArrayList victims = new ArrayList(); CollectZombies(victims);
    for (int i = 0; i < victims.Length; i++)
    {
        int victim = EntRefToEntIndex(victims.Get(i));
        if (victim == primary || !IsZombie(victim)) continue;
        float point[3]; ZombieCenter(victim, point);
        float distance = GetVectorDistance(center, point);
        if (distance > g_RasSplashRange.FloatValue || !VisibleBetween(origin, point, victim) || !VisibleBetween(center, point, victim)) continue;
        if (distance < distances[0])
        {
            distances[1] = distances[0]; references[1] = references[0];
            distances[0] = distance; references[0] = victims.Get(i);
        }
        else if (distance < distances[1]) { distances[1] = distance; references[1] = victims.Get(i); }
    }
    delete victims;
}

void ApplyRasenganDamage(int client, int victim, float quota)
{
    if (!IsZombie(victim) || g_RasBudget[client].remaining <= 0.0) return;
    int before = ZombieHealth(victim);
    float requested = IsCommon(victim) ? g_RasBudget[client].CommonKill(float(before)) : g_RasBudget[client].Limit(quota, float(before));
    int integerDamage = RoundToFloor(requested + 0.0001);
    if (integerDamage <= 0) return;
    int reference = EntIndexToEntRef(victim);
    // The fire-only tank resistance deliberately does not apply to Rasengan.
    SDKHooks_TakeDamage(victim, client, client, float(integerDamage), DMG_GENERIC);
    victim = EntRefToEntIndex(reference);
    int after = victim == INVALID_ENT_REFERENCE || !IsValidEntity(victim) ? 0 : ZombieHealth(victim);
    if (after < 0) after = 0;
    if (after < before) g_RasBudget[client].Account(float(before - after));
}

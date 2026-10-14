#if defined _chakra_core_included
    #endinput
#endif
#define _chakra_core_included

// Pure gameplay rules shared by the plugin and the SourcePawn runtime tests.
enum struct ChakraPool
{
    float amount;
    float maximum;
    float reserved;
    float regenAfter;

    void Reset(float maximum)
    {
        this.maximum = maximum;
        this.amount = maximum;
        this.reserved = 0.0;
        this.regenAfter = 0.0;
    }

    void SetMaximum(float maximum)
    {
        this.maximum = maximum;
        if (this.amount > maximum)
            this.amount = maximum;
    }

    bool Reserve(float cost, float now, float regenDelay)
    {
        if (cost <= 0.0 || this.reserved > 0.0 || this.amount < cost)
            return false;

        this.amount -= cost;
        this.reserved = cost;
        this.regenAfter = now + regenDelay;
        return true;
    }

    void Commit()
    {
        this.reserved = 0.0;
    }

    void Cancel()
    {
        this.amount += this.reserved;
        if (this.amount > this.maximum)
            this.amount = this.maximum;
        this.reserved = 0.0;
    }

    void Regenerate(float elapsed, float now, float rate)
    {
        if (this.reserved > 0.0 || now <= this.regenAfter || rate <= 0.0)
            return;

        // Only regenerate the portion of this tick after the delay expired.
        float available = now - this.regenAfter;
        if (elapsed > available)
            elapsed = available;
        if (elapsed <= 0.0)
            return;

        this.amount += elapsed * rate;
        if (this.amount > this.maximum)
            this.amount = this.maximum;
    }
}

stock float ChakraBlastDamage(float distance, float radius, float damage)
{
    if (radius <= 0.0 || distance < 0.0 || distance > radius)
        return 0.0;

    // The edge still kills ordinary infected; the center rewards accurate aim.
    return damage * (1.0 - 0.65 * distance / radius);
}

#define CHAKRA_TECHNIQUES 4
#define CHAKRA_SLOTS 3
#define JUTSU_FIREBALL 0
#define JUTSU_CLONE 1
#define JUTSU_GREATFIRE 2
#define JUTSU_RASENGAN 3

enum struct TechniqueLoadout
{
    bool assigned;
    int slots[CHAKRA_SLOTS];

    void Clear()
    {
        this.assigned = false;
        for (int i = 0; i < CHAKRA_SLOTS; i++)
            this.slots[i] = -1;
    }

    void Assign(int rank)
    {
        // 4P3 = 24 equiprobable ordered sets; no repeated techniques.
        int available[CHAKRA_TECHNIQUES] = {0, 1, 2, 3};
        int divisors[CHAKRA_SLOTS] = {6, 2, 1};
        rank %= 24;
        if (rank < 0)
            rank += 24;
        for (int slot = 0; slot < CHAKRA_SLOTS; slot++)
        {
            int choice = rank / divisors[slot];
            rank %= divisors[slot];
            this.slots[slot] = available[choice];
            for (int i = choice; i < CHAKRA_TECHNIQUES - slot - 1; i++)
                available[i] = available[i + 1];
        }
        this.assigned = true;
    }

    bool Contains(int technique)
    {
        if (!this.assigned)
            return false;
        for (int slot = 0; slot < CHAKRA_SLOTS; slot++)
            if (this.slots[slot] == technique)
                return true;
        return false;
    }
}

enum struct DamageWindow
{
    float started;
    float ends;
    float accounted;
    float total;

    void Begin(float now, float duration, float damage)
    {
        this.started = now;
        this.ends = now + duration;
        this.accounted = now;
        this.total = damage;
    }

    float NextSlice(float now)
    {
        if (this.ends <= this.started || now <= this.accounted)
            return 0.0;
        float until = now < this.ends ? now : this.ends;
        if (until <= this.accounted)
            return 0.0;
        float damage = this.total * (until - this.accounted) / (this.ends - this.started);
        this.accounted = until;
        return damage;
    }
}

enum struct RasenganBudget
{
    float ends;
    float remaining;
    float spent;

    void Begin(float now, float duration, float limit)
    {
        this.ends = now + duration;
        this.remaining = limit;
        this.spent = 0.0;
    }

    bool Active(float now)
    {
        return now < this.ends && this.remaining > 0.0;
    }

    float Limit(float proposed, float health)
    {
        if (proposed <= 0.0 || health <= 0.0 || this.remaining <= 0.0)
            return 0.0;
        if (proposed > health)
            proposed = health;
        if (proposed > this.remaining)
            proposed = this.remaining;
        return proposed;
    }

    float CommonKill(float health)
    {
        // The final ordinary zombie must still die instantly. Crossing the
        // threshold on this last kill terminates the technique immediately.
        return this.remaining > 0.0 && health > 0.0 ? health : 0.0;
    }

    void Account(float actual)
    {
        if (actual <= 0.0)
            return;
        this.spent += actual;
        this.remaining -= actual;
        if (this.remaining < 0.0)
            this.remaining = 0.0;
    }
}

stock bool ChakraInsideCone(float distance, float dot, float range, float minimumDot)
{
    return distance >= 0.0 && distance <= range && dot >= minimumDot;
}

stock int ChakraWholeDamage(float damage, float &fraction)
{
    float accumulated = damage + fraction;
    if (accumulated <= 0.0) return 0;
    int whole = RoundToFloor(accumulated + 0.0001);
    fraction = accumulated - float(whole);
    if (fraction < 0.0) fraction = 0.0;
    return whole;
}

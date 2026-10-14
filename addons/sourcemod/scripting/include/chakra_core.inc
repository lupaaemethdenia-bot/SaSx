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

float ChakraBlastDamage(float distance, float radius, float damage)
{
    if (radius <= 0.0 || distance < 0.0 || distance > radius)
        return 0.0;

    // The edge still kills ordinary infected; the center rewards accurate aim.
    return damage * (1.0 - 0.65 * distance / radius);
}

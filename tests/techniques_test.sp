#pragma semicolon 1
#pragma newdecls required
#include <shell>
#include "../addons/sourcemod/scripting/include/chakra_core.inc"

int g_Checks;
void Expect(bool condition, const char[] message)
{
    g_Checks++;
    if (!condition) { print(message); report_error(); }
}
bool Near(float actual, float expected)
{
    float difference = actual - expected;
    return difference > -0.001 && difference < 0.001;
}
public int main()
{
    TechniqueLoadout set;
    set.Clear();
    Expect(!set.Contains(0), "An unassigned character must not have an accidental fireball");
    bool seen[64];
    int counts[4][3];
    for (int rank = 0; rank < 24; rank++)
    {
        set.Assign(rank);
        Expect(set.assigned, "The character must receive an assigned loadout");
        int encoded = set.slots[0] * 16 + set.slots[1] * 4 + set.slots[2];
        Expect(!seen[encoded], "All 24 ordered loadouts must be distinct");
        seen[encoded] = true;
        int mask;
        for (int slot = 0; slot < 3; slot++)
        {
            int tech = set.slots[slot];
            Expect(tech >= 0 && tech < 4, "Every slot must identify a real technique");
            Expect((mask & (1 << tech)) == 0, "A character cannot receive duplicate techniques");
            mask |= 1 << tech;
            counts[tech][slot]++;
            Expect(set.Contains(tech), "The loadout must report every assigned technique");
        }
        for (int tech = 0; tech < 4; tech++)
            Expect(set.Contains(tech) == ((mask & (1 << tech)) != 0), "Absent techniques must not appear in the loadout");
    }
    for (int tech = 0; tech < 4; tech++)
        for (int slot = 0; slot < 3; slot++)
            Expect(counts[tech][slot] == 6, "The distribution must be uniform for each technique and each slot");

    DamageWindow fire;
    fire.Begin(10.0, 3.0, 300.0 * 1.5);
    float fraction;
    int dealt;
    for (int tick = 1; tick <= 60; tick++)
        dealt += ChakraWholeDamage(fire.NextSlice(10.0 + float(tick) * 0.05), fraction);
    Expect(dealt == 450, "Three seconds of contact must deliver exactly 150 percent of fireball damage");
    Expect(Near(fire.NextSlice(20.0), 0.0), "Great fire must not damage after the end of its window");
    fire.Begin(1.0, 3.0, 450.0);
    float total = fire.NextSlice(1.1) + fire.NextSlice(1.85) + fire.NextSlice(2.6) + fire.NextSlice(5.0);
    Expect(Near(total, 450.0), "Irregular timer intervals must not increase or reduce total damage");
    Expect(Near(fire.NextSlice(5.0), 0.0), "Repeating a timer timestamp must not deal damage twice");
    fire.Begin(0.0, 3.0, 450.0);
    Expect(Near(fire.NextSlice(1.5), 225.0), "Half the contact window must deal half the total");
    Expect(Near(fire.NextSlice(1.0), 0.0), "Time moving backwards must not emit a damage slice");
    Expect(Near(fire.NextSlice(3.0), 225.0), "Earlier accounting must remain intact after a backward timestamp");
    Expect(ChakraInsideCone(900.0, 0.5, 900.0, 0.4226), "A forward target on the range boundary must qualify");
    Expect(!ChakraInsideCone(901.0, 0.5, 900.0, 0.4226), "A target beyond the range must not qualify");
    Expect(!ChakraInsideCone(100.0, -1.0, 900.0, 0.4226), "A target behind the player must not qualify");

    RasenganBudget ras;
    ras.Begin(10.0, 10.0, 4000.0);
    Expect(ras.Active(10.0), "Rasengan becomes active after preparation");
    Expect(ras.Active(19.99), "Rasengan remains active before ten seconds");
    Expect(!ras.Active(20.0), "Rasengan expires at ten seconds even without hitting targets");
    Expect(Near(ras.remaining, 4000.0), "Waiting must not consume damage budget");
    fraction = 0.0;
    dealt = 0;
    for (int tick = 0; tick < 30; tick++)
    {
        int dose = ChakraWholeDamage(4000.0 / 1.5 * 0.05, fraction);
        float accepted = ras.Limit(float(dose), 8000.0);
        ras.Account(accepted);
        dealt += RoundToFloor(accepted);
    }
    Expect(dealt == 4000, "An isolated tank must receive the full 4000 in 1.5 seconds of contact");
    Expect(!ras.Active(11.5), "Rasengan ends early when its budget is exhausted");
    Expect(Near(ras.Limit(100.0, 100.0), 0.0), "No further targets may receive damage after exhaustion");

    ras.Begin(0.0, 10.0, 4000.0);
    float commonKill = ras.Limit(50.0, 50.0);
    ras.Account(commonKill);
    ras.Account(ras.Limit(50.0, 50.0));
    ras.Account(ras.Limit(50.0, 50.0));
    Expect(Near(commonKill, 50.0), "A normal common receives lethal damage immediately");
    Expect(Near(ras.remaining, 3850.0), "The primary and two bonus kills share the same budget");
    ras.Account(0.0);
    Expect(Near(ras.remaining, 3850.0), "Blocked damage must not consume the budget");
    Expect(Near(ras.Limit(5000.0, 50.0), 50.0), "Overkill must not consume fictional damage");

    ras.Begin(0.0, 10.0, 80.0);
    ras.Account(ras.Limit(133.0, 50.0));
    Expect(Near(ras.remaining, 30.0), "A dying primary target consumes only its remaining health");
    Expect(Near(ras.Limit(133.0, 100.0), 30.0), "The final damage event is clipped to the remaining budget");
    ras.Account(30.0);
    Expect(!ras.Active(1.0), "Primary and secondary targets cannot exceed the shared cap");
    Expect(Near(ras.Limit(-1.0, 100.0), 0.0), "Negative damage cannot grant damage budget");
    ras.Begin(0.0, 10.0, 30.0);
    Expect(Near(ras.CommonKill(50.0), 50.0), "The final ordinary zombie must still die instantly");
    ras.Account(50.0);
    Expect(Near(ras.spent, 50.0), "Record actual final damage even when it crosses the threshold");
    Expect(!ras.Active(0.1), "Crossing the threshold terminates Rasengan immediately");
    Expect(Near(ras.CommonKill(50.0), 0.0), "No bonus kill is allowed after crossing the threshold");

    ChakraPool chakra;
    chakra.Reset(100.0);
    Expect(chakra.Reserve(80.0, 1.0, 5.0), "The 80-chakra Rasengan is affordable from a full pool");
    chakra.Commit();
    Expect(Near(chakra.amount, 20.0), "Rasengan pays once at activation, not on each hit");
    Expect(!chakra.Reserve(80.0, 2.0, 5.0), "Cannot reactivate Rasengan without enough chakra");
    printf("PASS: %d technique assertions\n", g_Checks);
    return 0;
}

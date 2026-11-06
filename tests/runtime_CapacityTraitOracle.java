/** Reproduces the installed bytecode's primitive float32 arithmetic only. */
public class runtime_CapacityTraitOracle {
    public static void main(String[] args) {
        StringBuilder json = new StringBuilder("{\"source\":\"installed B42.21 getEffectiveCapacity float32 expression\",\"capacities\":[");
        for (int capacity = 50; capacity <= 1000; capacity++) {
            if (capacity > 50) json.append(',');
            int organized = (int) Math.max(capacity * 1.3f, capacity + 1.0f);
            int disorganized = (int) Math.max(capacity * 0.7f, 1.0f);
            json.append('[').append(capacity).append(',').append(organized).append(',').append(disorganized).append(']');
        }
        json.append("]}");
        System.out.println(json.toString());
    }
}

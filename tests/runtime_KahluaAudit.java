import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;

/** Runs only standalone Kahlua environments; does not initialize a game or world. */
public class runtime_KahluaAudit {
    public static void main(String[] args) throws Exception {
        Class<?> platformClass = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Object platform = platformClass.newInstance();
        Object environment = platformClass.getMethod("newEnvironment").invoke(platform);
        Class<?> platformInterface = Class.forName("se.krka.kahlua.vm.Platform");
        Class<?> tableInterface = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> javaFunction = Class.forName("se.krka.kahlua.vm.JavaFunction");
        Object print = Proxy.newProxyInstance(javaFunction.getClassLoader(), new Class<?>[] {javaFunction}, (proxy, method, values) -> {
            if (method.getName().equals("call")) {
                Object frame = values[0];
                int count = ((Integer) values[1]).intValue();
                Method get = frame.getClass().getMethod("get", int.class);
                StringBuilder message = new StringBuilder();
                for (int index = 0; index < count; index++) {
                    if (index > 0) message.append('\t');
                    message.append(get.invoke(frame, index));
                }
                System.out.println(message.toString());
                return Integer.valueOf(0);
            }
            if (method.getName().equals("toString")) return "runtime audit print";
            return null;
        });
        tableInterface.getMethod("rawset", Object.class, Object.class).invoke(environment, "print", print);
        Object float32 = Proxy.newProxyInstance(javaFunction.getClassLoader(), new Class<?>[] {javaFunction}, (proxy, method, values) -> {
            if (method.getName().equals("call")) {
                Object frame = values[0];
                Number value = (Number) frame.getClass().getMethod("get", int.class).invoke(frame, 0);
                Double rounded = Double.valueOf((double) value.floatValue());
                return frame.getClass().getMethod("push", Object.class).invoke(frame, rounded);
            }
            if (method.getName().equals("toString")) return "native float32 cast";
            return null;
        });
        tableInterface.getMethod("rawset", Object.class, Object.class).invoke(environment, "nativeFloat32", float32);
        Class<?> threadClass = Class.forName("se.krka.kahlua.vm.KahluaThread");
        Object thread = threadClass.getConstructor(platformInterface, tableInterface).newInstance(platform, environment);
        threadClass.getField("debugOwnerThread").set(thread, Thread.currentThread());
        Method load = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
                .getMethod("loadstring", String.class, String.class, tableInterface);
        Method call = threadClass.getMethod("pcall", Object.class, Object[].class);
        for (String filename : args) {
            String source = new String(Files.readAllBytes(Paths.get(filename)), StandardCharsets.UTF_8);
            Object closure = load.invoke(null, source, filename, environment);
            Object[] result = (Object[]) call.invoke(thread, closure, new Object[0]);
            System.out.println(filename + ": " + Arrays.toString(result));
            if (!Boolean.TRUE.equals(result[0])) {
                throw new RuntimeException("Kahlua audit failed: " + Arrays.toString(result));
            }
        }
    }
}

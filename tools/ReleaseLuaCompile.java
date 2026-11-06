import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.lang.reflect.*;
public final class ReleaseLuaCompile {
  public static void main(String[] args) throws Exception {
    Class<?> p=Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
    Object env=p.getMethod("newEnvironment").invoke(p.newInstance());
    Method load=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,Class.forName("se.krka.kahlua.vm.KahluaTable"));
    int count=0;
    for(String file:args) { load.invoke(null,new String(Files.readAllBytes(Paths.get(file)),StandardCharsets.UTF_8),file,env); count++; }
    System.out.println("LUA_COMPILE files="+count+" PASS");
  }
}

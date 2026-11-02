allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Legacy plugins (e.g. receive_sharing_intent 1.8.1) declare an old Java
// target while their Kotlin tasks default to the running JDK (21), which
// fails AGP's JVM-target validation (pipeline 44). Align each module's
// Kotlin bytecode target to its own javac target: the app module keeps 17,
// old plugins compile their declared 11, nothing else moves. Reflection
// because the Kotlin plugin classes are not on this script's compile
// classpath (applied `false` in settings).
subprojects {
    afterEvaluate {
        val javac =
            tasks.findByName("compileDebugJavaWithJavac") as? JavaCompile
                ?: return@afterEvaluate
        val target =
            when (javac.targetCompatibility) {
                "1.8" -> "JVM_1_8"
                "11" -> "JVM_11"
                "17" -> "JVM_17"
                "21" -> "JVM_21"
                else -> return@afterEvaluate
            }
        tasks.configureEach {
            val isKotlinCompile =
                generateSequence<Class<*>>(javaClass) { it.superclass }
                    .any { it.canonicalName == "org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile" }
            if (isKotlinCompile) {
                runCatching {
                    val loader = javaClass.classLoader
                    val options = javaClass.getMethod("getCompilerOptions").invoke(this)
                    val jvmTarget = options.javaClass.getMethod("getJvmTarget").invoke(options)
                    val enumClass =
                        Class.forName("org.jetbrains.kotlin.gradle.dsl.JvmTarget", false, loader)
                    val value = enumClass.getMethod("valueOf", String::class.java).invoke(null, target)
                    jvmTarget.javaClass.getMethod("set", Any::class.java).invoke(jvmTarget, value)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

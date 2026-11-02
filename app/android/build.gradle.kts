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

// Legacy plugins (e.g. receive_sharing_intent 1.8.1) declare no compileOptions,
// so AGP floors their javac at 11 while KGP defaults Kotlin to the running
// JDK (21) — AGP's JVM-target validation fails (pipeline 44). Each module's
// Kotlin bytecode target now lazily follows its own compileDebugJavaWithJavac
// target (app keeps 17; the provider resolves at execution, after all
// configuration). No afterEvaluate — Flutter's evaluationDependsOn(":app")
// can evaluate projects before this block reaches them — and no AGP/KGP
// imports, since neither plugin is on this script's compile classpath.
fun kotlinTargetNameFor(javac: JavaCompile?): String? =
    when (javac?.targetCompatibility) {
        "1.8" -> "JVM_1_8"
        "11" -> "JVM_11"
        "17" -> "JVM_17"
        "21" -> "JVM_21"
        else -> null
    }

fun alignKotlinJvmTarget(task: Task) {
    runCatching {
        val loader = task.javaClass.classLoader
        val options = task.javaClass.getMethod("getCompilerOptions").invoke(task)
        val jvmTarget = options.javaClass.getMethod("getJvmTarget").invoke(options)
        val enumClass =
            Class.forName("org.jetbrains.kotlin.gradle.dsl.JvmTarget", false, loader)
        val current = jvmTarget.javaClass.getMethod("get").invoke(jvmTarget)
        val project = task.project
        val mapped =
            project.providers
                .provider {
                    val javac =
                        project.tasks.findByName("compileDebugJavaWithJavac") as? JavaCompile
                    kotlinTargetNameFor(javac)
                        ?.let { enumClass.getMethod("valueOf", String::class.java).invoke(null, it) }
                }.map { it ?: current }
        val providerClass = Class.forName("org.gradle.api.provider.Provider", false, loader)
        jvmTarget.javaClass.getMethod("set", providerClass).invoke(jvmTarget, mapped)
    }
}

subprojects {
    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        tasks.configureEach {
            val isKotlinJvmCompile =
                generateSequence<Class<*>>(javaClass) { it.superclass }
                    .any { it.canonicalName == "org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile" }
            if (isKotlinJvmCompile) {
                alignKotlinJvmTarget(this)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

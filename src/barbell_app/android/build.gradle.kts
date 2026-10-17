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
// Plugin modules each pick their own Java target (11 or 17), compileSdk and
// NDK. Flutter applies KGP to all of them (android.builtInKotlin=false), and
// Kotlin defaults to the Gradle JDK's target, so Java-11 plugins fail the JVM
// target check. Align every plugin with :app. Must be registered before the
// evaluationDependsOn block below, which evaluates :app.
subprojects {
    afterEvaluate {
        val lib = extensions.findByType<com.android.build.api.dsl.LibraryExtension>() ?: return@afterEvaluate
        val app = project(":app").extensions.getByType<com.android.build.api.dsl.ApplicationExtension>()
        lib.compileSdk = app.compileSdk
        lib.ndkVersion = app.ndkVersion
        lib.compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

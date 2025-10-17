// Top-level build script configuration
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.10")
        classpath("com.google.gms:google-services:4.4.0")
    }
}

// Shared repositories for all subprojects
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Custom build directory for root project
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Custom build directory for each subproject
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Ensure subprojects evaluate after :app
subprojects {
    project.evaluationDependsOn(":app")
}

// Clean task to delete custom build directory
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
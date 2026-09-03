pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Motion tokens for the pill family with iOS-like blur and appear transitions.
 * Durations collapse to zero when animations are off.
 */
Singleton {
    readonly property real mult: Appearance.animationsEnabled
        ? ((Config.options?.performance?.reduceAnimations ?? false) ? 0.4 : 1)
        : 0

    readonly property int fast: Math.round(140 * mult)
    readonly property int standard: Math.round(300 * mult)
    readonly property int morph: Math.round(420 * mult)
    readonly property int shapeshift: Math.round(820 * mult)
    readonly property int glide: Math.round(260 * mult)
    readonly property int heat: Math.round(1100 * mult)
    readonly property int pulse: Math.round(420 * mult)

    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeMorph: Easing.BezierSpline

    /**
     * Liquid morph curve, cubic-bezier(0.165, 0.84, 0.44, 1) / cubic-bezier(0.16, 1, 0.3, 1).
     * Front-loaded like an exponential chase with a smooth settle tail.
     */
    readonly property var morphCurve: [0.16, 1, 0.3, 1, 1, 1]
    readonly property var iosAppearCurve: [0.165, 0.84, 0.44, 1]

    // Paramètres dédiés à l'effet de flou et d'apparition style iOS (@keyframes appear)
    readonly property int appearDuration: Math.round(1000 * mult)
    readonly property real initialBlur: 5.0
    readonly property real finalBlur: 0.0

    readonly property real rSmall: 7
    readonly property real rTile: 13

    // --- Spring "liquide" style iOS Dynamic Island ---
    // Un SpringAnimation physique (masse/ressort/amortissement) rend le
    // morph beaucoup plus organique qu'une courbe bezier interpolée :
    // léger overshoot puis settle, exactement l'effet "élastique" d'iOS.
    // spring* sert au morph normal (surfaces, changements de mode marqués),
    // hopSpring* sert au petit hop rest<->hover, plus sec et plus rapide.
    readonly property real springMass: 1.0
    readonly property real springStiffness: Appearance.animationsEnabled ? 320 : 100000
    readonly property real springDamping: 26
    readonly property real springEpsilon: 0.25

    readonly property real hopSpringStiffness: Appearance.animationsEnabled ? 480 : 100000
    readonly property real hopSpringDamping: 30
}
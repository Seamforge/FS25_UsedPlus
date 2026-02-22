/**
 * FS25_UsedPlus Icon Generator
 *
 * Generates custom icons for the mod's GUI dialogs using Sharp.
 * Icons are created as SVG, rendered to PNG, then converted to DDS.
 *
 * Usage: node tools/generateIcons.js
 *
 * Requirements:
 *   - npm install sharp
 *   - GIANTS Texture Tool (for DDS conversion)
 */

const sharp = require('sharp');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

// Configuration
const CONFIG = {
    outputDir: path.join(__dirname, '..', 'gui', 'icons'),
    iconSize: 256,  // v2.8.1: Increased from 64 for better rendering in FS25
    textureTool: 'C:/Program Files/GIANTS Software/GIANTS_Editor_10.0.11/tools/textureTool.exe',
    convertToDDS: true  // DDS required to avoid raw format warnings in game log
};

// Color palette - consistent with FS25 UI aesthetic
const COLORS = {
    // Primary colors
    green: '#4CAF50',
    greenDark: '#2E7D32',
    orange: '#FF9800',
    orangeDark: '#E65100',
    blue: '#2196F3',
    blueDark: '#1565C0',
    purple: '#9C27B0',
    purpleDark: '#6A1B9A',
    red: '#F44336',
    redDark: '#C62828',
    teal: '#00BCD4',
    tealDark: '#00838F',
    gray: '#607D8B',
    grayDark: '#37474F',

    // Text/icon colors
    white: '#FFFFFF',
    lightGray: '#E0E0E0',
    darkBg: '#1a1a24'
};

/**
 * SVG Icon Definitions
 * Each icon is defined as an SVG path or shape combination
 */
const ICONS = {
    // === Field Service Kit Mode Icons ===

    // Repair/Diagnose - Wrench icon
    fsk_repair: {
        name: 'fsk_repair',
        bgColor: COLORS.green,
        bgColorDark: COLORS.greenDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.green}"/>
                        <stop offset="100%" style="stop-color:${COLORS.greenDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bg)"/>
                <g transform="translate(12, 12)" fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>
                </g>
            </svg>`
    },

    // Warning/Malfunctions - Triangle with exclamation
    fsk_warning: {
        name: 'fsk_warning',
        bgColor: COLORS.orange,
        bgColorDark: COLORS.orangeDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgWarn" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.orange}"/>
                        <stop offset="100%" style="stop-color:${COLORS.orangeDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgWarn)"/>
                <g transform="translate(12, 10)" fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
                    <line x1="12" y1="9" x2="12" y2="13"/>
                    <circle cx="12" cy="17" r="0.5" fill="${COLORS.white}"/>
                </g>
            </svg>`
    },

    // Tire Service - Wheel/tire icon
    fsk_tire: {
        name: 'fsk_tire',
        bgColor: COLORS.blue,
        bgColorDark: COLORS.blueDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgTire" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.blue}"/>
                        <stop offset="100%" style="stop-color:${COLORS.blueDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgTire)"/>
                <g transform="translate(12, 12)" fill="none" stroke="${COLORS.white}" stroke-width="2.5">
                    <circle cx="20" cy="20" r="18"/>
                    <circle cx="20" cy="20" r="10"/>
                    <circle cx="20" cy="20" r="3" fill="${COLORS.white}"/>
                    <line x1="20" y1="2" x2="20" y2="10"/>
                    <line x1="20" y1="30" x2="20" y2="38"/>
                    <line x1="2" y1="20" x2="10" y2="20"/>
                    <line x1="30" y1="20" x2="38" y2="20"/>
                </g>
            </svg>`
    },

    // RVB/Diagnostics - Chart/graph icon
    fsk_diagnostics: {
        name: 'fsk_diagnostics',
        bgColor: COLORS.purple,
        bgColorDark: COLORS.purpleDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgDiag" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.purple}"/>
                        <stop offset="100%" style="stop-color:${COLORS.purpleDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgDiag)"/>
                <g transform="translate(12, 12)" fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="4" y1="36" x2="4" y2="20"/>
                    <line x1="14" y1="36" x2="14" y2="12"/>
                    <line x1="24" y1="36" x2="24" y2="24"/>
                    <line x1="34" y1="36" x2="34" y2="4"/>
                    <line x1="0" y1="36" x2="40" y2="36"/>
                </g>
            </svg>`
    },

    // === Finance/Menu Icons ===

    // Finance Manager - Dollar/money icon
    finance: {
        name: 'finance',
        bgColor: COLORS.green,
        bgColorDark: COLORS.greenDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgFin" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.green}"/>
                        <stop offset="100%" style="stop-color:${COLORS.greenDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgFin)"/>
                <g transform="translate(18, 8)" fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="14" y1="2" x2="14" y2="46"/>
                    <path d="M24 12H9a6 6 0 0 0 0 12h10a6 6 0 0 1 0 12H4"/>
                </g>
            </svg>`
    },

    // Used Vehicle Search - Magnifying glass with car
    search: {
        name: 'search',
        bgColor: COLORS.teal,
        bgColorDark: COLORS.tealDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgSearch" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.teal}"/>
                        <stop offset="100%" style="stop-color:${COLORS.tealDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgSearch)"/>
                <g transform="translate(12, 12)" fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <circle cx="16" cy="16" r="12"/>
                    <line x1="24.5" y1="24.5" x2="36" y2="36"/>
                </g>
            </svg>`
    },

    // Inspect Vehicle - Eye icon
    inspect: {
        name: 'inspect',
        bgColor: COLORS.blue,
        bgColorDark: COLORS.blueDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgInsp" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.blue}"/>
                        <stop offset="100%" style="stop-color:${COLORS.blueDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgInsp)"/>
                <g transform="translate(8, 16)" fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M1 16s8-12 23-12 23 12 23 12-8 12-23 12S1 16 1 16z"/>
                    <circle cx="24" cy="16" r="6"/>
                </g>
            </svg>`
    },

    // Loan/Credit - Bank/building icon
    loan: {
        name: 'loan',
        bgColor: COLORS.gray,
        bgColorDark: COLORS.grayDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgLoan" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.gray}"/>
                        <stop offset="100%" style="stop-color:${COLORS.grayDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgLoan)"/>
                <g transform="translate(10, 10)" fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="22,4 4,14 4,18 40,18 40,14"/>
                    <line x1="4" y1="40" x2="40" y2="40"/>
                    <line x1="10" y1="18" x2="10" y2="40"/>
                    <line x1="22" y1="18" x2="22" y2="40"/>
                    <line x1="34" y1="18" x2="34" y2="40"/>
                </g>
            </svg>`
    },

    // Success checkmark
    success: {
        name: 'success',
        bgColor: COLORS.green,
        bgColorDark: COLORS.greenDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgSucc" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.green}"/>
                        <stop offset="100%" style="stop-color:${COLORS.greenDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgSucc)"/>
                <g transform="translate(14, 16)" fill="none" stroke="${COLORS.white}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="4,18 14,28 32,6"/>
                </g>
            </svg>`
    },

    // Failure X
    failure: {
        name: 'failure',
        bgColor: COLORS.red,
        bgColorDark: COLORS.redDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgFail" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.red}"/>
                        <stop offset="100%" style="stop-color:${COLORS.redDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgFail)"/>
                <g transform="translate(18, 18)" fill="none" stroke="${COLORS.white}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="0" y1="0" x2="28" y2="28"/>
                    <line x1="28" y1="0" x2="0" y2="28"/>
                </g>
            </svg>`
    },

    // Info icon
    info: {
        name: 'info',
        bgColor: COLORS.blue,
        bgColorDark: COLORS.blueDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgInfo" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.blue}"/>
                        <stop offset="100%" style="stop-color:${COLORS.blueDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgInfo)"/>
                <g transform="translate(24, 14)" fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <circle cx="8" cy="4" r="1" fill="${COLORS.white}"/>
                    <line x1="8" y1="14" x2="8" y2="34"/>
                </g>
            </svg>`
    },

    // Engine system
    sys_engine: {
        name: 'sys_engine',
        bgColor: '#455A64',
        bgColorDark: '#263238',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgEng" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#455A64"/>
                        <stop offset="100%" style="stop-color:#263238"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgEng)"/>
                <g transform="translate(10, 14)" fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="8" y="8" width="28" height="20" rx="2"/>
                    <line x1="0" y1="14" x2="8" y2="14"/>
                    <line x1="0" y1="22" x2="8" y2="22"/>
                    <line x1="36" y1="18" x2="44" y2="18"/>
                    <line x1="18" y1="0" x2="18" y2="8"/>
                    <line x1="26" y1="0" x2="26" y2="8"/>
                    <circle cx="22" cy="18" r="6"/>
                </g>
            </svg>`
    },

    // Electrical system
    sys_electrical: {
        name: 'sys_electrical',
        bgColor: '#FFC107',
        bgColorDark: '#FF8F00',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgElec" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#FFC107"/>
                        <stop offset="100%" style="stop-color:#FF8F00"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgElec)"/>
                <g transform="translate(18, 8)" fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <polygon points="16,0 6,22 14,22 12,46 26,18 18,18" fill="${COLORS.white}"/>
                </g>
            </svg>`
    },

    // Hydraulic system
    sys_hydraulic: {
        name: 'sys_hydraulic',
        bgColor: '#E91E63',
        bgColorDark: '#AD1457',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgHyd" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#E91E63"/>
                        <stop offset="100%" style="stop-color:#AD1457"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgHyd)"/>
                <g transform="translate(12, 10)" fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="0" y="10" width="16" height="24" rx="2"/>
                    <rect x="24" y="4" width="16" height="36" rx="2"/>
                    <line x1="16" y1="22" x2="24" y2="22"/>
                    <line x1="8" y1="4" x2="8" y2="10"/>
                    <line x1="32" y1="40" x2="32" y2="46"/>
                </g>
            </svg>`
    },

    // Oil/fluid
    oil: {
        name: 'oil',
        bgColor: '#795548',
        bgColorDark: '#4E342E',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgOil" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#795548"/>
                        <stop offset="100%" style="stop-color:#4E342E"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgOil)"/>
                <g transform="translate(16, 8)" fill="${COLORS.white}" stroke="${COLORS.white}" stroke-width="1">
                    <path d="M16 4 C16 4 4 20 4 32 C4 40 9 46 16 46 C23 46 28 40 28 32 C28 20 16 4 16 4Z"/>
                </g>
            </svg>`
    },

    // Service truck
    service_truck: {
        name: 'service_truck',
        bgColor: COLORS.orange,
        bgColorDark: COLORS.orangeDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgTruck" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.orange}"/>
                        <stop offset="100%" style="stop-color:${COLORS.orangeDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgTruck)"/>
                <g transform="translate(6, 16)" fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="2" y="4" width="30" height="20" rx="2"/>
                    <path d="M32 12 L44 12 L50 20 L50 24 L32 24 Z"/>
                    <circle cx="12" cy="28" r="5"/>
                    <circle cx="42" cy="28" r="5"/>
                    <line x1="17" y1="28" x2="37" y2="28"/>
                </g>
            </svg>`
    },

    // === Status Icons (for inline row indicators) ===

    // Status: Good/On-time/Success - green circle with checkmark
    status_good: {
        name: 'status_good',
        bgColor: COLORS.green,
        bgColorDark: COLORS.greenDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgStGood" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.green}"/>
                        <stop offset="100%" style="stop-color:${COLORS.greenDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgStGood)"/>
                <circle cx="32" cy="32" r="20" fill="none" stroke="${COLORS.white}" stroke-width="3"/>
                <polyline points="22,32 28,38 42,24" fill="none" stroke="${COLORS.white}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>`
    },

    // Status: Warning/Attention - orange circle with exclamation
    status_warning: {
        name: 'status_warning',
        bgColor: COLORS.orange,
        bgColorDark: COLORS.orangeDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgStWarn" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.orange}"/>
                        <stop offset="100%" style="stop-color:${COLORS.orangeDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgStWarn)"/>
                <circle cx="32" cy="32" r="20" fill="none" stroke="${COLORS.white}" stroke-width="3"/>
                <line x1="32" y1="20" x2="32" y2="34" stroke="${COLORS.white}" stroke-width="4" stroke-linecap="round"/>
                <circle cx="32" cy="42" r="2.5" fill="${COLORS.white}"/>
            </svg>`
    },

    // Status: Bad/Overdue/Failed - red circle with X
    status_bad: {
        name: 'status_bad',
        bgColor: COLORS.red,
        bgColorDark: COLORS.redDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgStBad" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.red}"/>
                        <stop offset="100%" style="stop-color:${COLORS.redDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgStBad)"/>
                <circle cx="32" cy="32" r="20" fill="none" stroke="${COLORS.white}" stroke-width="3"/>
                <line x1="24" y1="24" x2="40" y2="40" stroke="${COLORS.white}" stroke-width="4" stroke-linecap="round"/>
                <line x1="40" y1="24" x2="24" y2="40" stroke="${COLORS.white}" stroke-width="4" stroke-linecap="round"/>
            </svg>`
    },

    // Status: Pending/Waiting - blue circle with hourglass/clock
    status_pending: {
        name: 'status_pending',
        bgColor: COLORS.blue,
        bgColorDark: COLORS.blueDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgStPend" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.blue}"/>
                        <stop offset="100%" style="stop-color:${COLORS.blueDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgStPend)"/>
                <circle cx="32" cy="32" r="20" fill="none" stroke="${COLORS.white}" stroke-width="3"/>
                <circle cx="32" cy="32" r="2" fill="${COLORS.white}"/>
                <line x1="32" y1="32" x2="32" y2="20" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round"/>
                <line x1="32" y1="32" x2="40" y2="36" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round"/>
            </svg>`
    },

    // === Trend Icons ===

    // Trend: Up/Improving - green upward arrow
    trend_up: {
        name: 'trend_up',
        bgColor: COLORS.green,
        bgColorDark: COLORS.greenDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgTrUp" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.green}"/>
                        <stop offset="100%" style="stop-color:${COLORS.greenDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgTrUp)"/>
                <path d="M32 14 L48 34 L40 34 L40 50 L24 50 L24 34 L16 34 Z" fill="${COLORS.white}"/>
            </svg>`
    },

    // Trend: Down/Declining - red downward arrow
    trend_down: {
        name: 'trend_down',
        bgColor: COLORS.red,
        bgColorDark: COLORS.redDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgTrDn" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.red}"/>
                        <stop offset="100%" style="stop-color:${COLORS.redDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgTrDn)"/>
                <path d="M32 50 L48 30 L40 30 L40 14 L24 14 L24 30 L16 30 Z" fill="${COLORS.white}"/>
            </svg>`
    },

    // Trend: Flat/Stable - gray horizontal arrow
    trend_flat: {
        name: 'trend_flat',
        bgColor: COLORS.gray,
        bgColorDark: COLORS.grayDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgTrFlat" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.gray}"/>
                        <stop offset="100%" style="stop-color:${COLORS.grayDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgTrFlat)"/>
                <path d="M50 32 L38 20 L38 26 L14 26 L14 38 L38 38 L38 44 Z" fill="${COLORS.white}"/>
            </svg>`
    },

    // === Finance/Credit Icons ===

    // Credit score - gold star badge
    credit_score: {
        name: 'credit_score',
        bgColor: '#FFB300',
        bgColorDark: '#FF8F00',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgCredit" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#FFB300"/>
                        <stop offset="100%" style="stop-color:#FF8F00"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgCredit)"/>
                <polygon points="32,10 38,26 54,26 41,36 46,52 32,42 18,52 23,36 10,26 26,26" fill="${COLORS.white}"/>
            </svg>`
    },

    // Calendar - for payment schedules
    calendar: {
        name: 'calendar',
        bgColor: COLORS.blue,
        bgColorDark: COLORS.blueDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgCal" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.blue}"/>
                        <stop offset="100%" style="stop-color:${COLORS.blueDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgCal)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="12" y="16" width="40" height="38" rx="4"/>
                    <line x1="12" y1="28" x2="52" y2="28"/>
                    <line x1="22" y1="10" x2="22" y2="22"/>
                    <line x1="42" y1="10" x2="42" y2="22"/>
                    <rect x="20" y="36" width="8" height="8" fill="${COLORS.white}" rx="1"/>
                </g>
            </svg>`
    },

    // Percentage - for interest rates
    percentage: {
        name: 'percentage',
        bgColor: COLORS.orange,
        bgColorDark: COLORS.orangeDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgPct" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.orange}"/>
                        <stop offset="100%" style="stop-color:${COLORS.orangeDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgPct)"/>
                <circle cx="22" cy="22" r="7" fill="none" stroke="${COLORS.white}" stroke-width="3"/>
                <circle cx="42" cy="42" r="7" fill="none" stroke="${COLORS.white}" stroke-width="3"/>
                <line x1="46" y1="18" x2="18" y2="46" stroke="${COLORS.white}" stroke-width="4" stroke-linecap="round"/>
            </svg>`
    },

    // === Navigation Icons ===

    // Arrow left - previous/navigate
    arrow_left: {
        name: 'arrow_left',
        bgColor: COLORS.gray,
        bgColorDark: COLORS.grayDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgArrL" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.gray}"/>
                        <stop offset="100%" style="stop-color:${COLORS.grayDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgArrL)"/>
                <polyline points="38,14 22,32 38,50" fill="none" stroke="${COLORS.white}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>`
    },

    // Arrow right - next/navigate
    arrow_right: {
        name: 'arrow_right',
        bgColor: COLORS.gray,
        bgColorDark: COLORS.grayDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgArrR" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.gray}"/>
                        <stop offset="100%" style="stop-color:${COLORS.grayDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgArrR)"/>
                <polyline points="26,14 42,32 26,50" fill="none" stroke="${COLORS.white}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>`
    },

    // === Purchase Mode Icons ===

    // Cash - dollar bill for cash purchases
    cash: {
        name: 'cash',
        bgColor: COLORS.green,
        bgColorDark: COLORS.greenDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgCash" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.green}"/>
                        <stop offset="100%" style="stop-color:${COLORS.greenDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgCash)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <rect x="8" y="16" width="48" height="32" rx="3"/>
                    <circle cx="32" cy="32" r="10"/>
                    <line x1="32" y1="26" x2="32" y2="38"/>
                    <path d="M28 29 Q32 26 36 29 Q32 32 28 29"/>
                    <path d="M28 35 Q32 38 36 35 Q32 32 28 35"/>
                </g>
            </svg>`
    },

    // Lease - key icon for lease/rental
    lease: {
        name: 'lease',
        bgColor: COLORS.purple,
        bgColorDark: COLORS.purpleDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgLease" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.purple}"/>
                        <stop offset="100%" style="stop-color:${COLORS.purpleDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgLease)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <circle cx="22" cy="24" r="12"/>
                    <circle cx="22" cy="24" r="4"/>
                    <line x1="30" y1="32" x2="52" y2="54"/>
                    <line x1="42" y1="44" x2="50" y2="36"/>
                    <line x1="48" y1="50" x2="54" y2="44"/>
                </g>
            </svg>`
    },

    // Trade-in - exchange/swap arrows
    trade_in: {
        name: 'trade_in',
        bgColor: COLORS.teal,
        bgColorDark: COLORS.tealDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgTrade" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.teal}"/>
                        <stop offset="100%" style="stop-color:${COLORS.tealDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgTrade)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="48,22 54,22 54,28"/>
                    <path d="M54 22 L38 38 Q32 44 26 38 L10 22"/>
                    <polyline points="16,42 10,42 10,36"/>
                    <path d="M10 42 L26 26 Q32 20 38 26 L54 42"/>
                </g>
            </svg>`
    },

    // Sale - for "Your Sales" section (tag/label icon)
    sale: {
        name: 'sale',
        bgColor: '#43A047',
        bgColorDark: '#2E7D32',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgSale" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#43A047"/>
                        <stop offset="100%" style="stop-color:#2E7D32"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgSale)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M12 32 L12 16 Q12 12 16 12 L32 12 L52 32 L32 52 L12 32"/>
                    <circle cx="24" cy="24" r="4" fill="${COLORS.white}"/>
                </g>
            </svg>`
    },

    // === v2.9.5: Visual Enhancement Icons ===

    // Loan Document - paper with $ sign for loan/financing contexts
    loan_doc: {
        name: 'loan_doc',
        bgColor: COLORS.blue,
        bgColorDark: COLORS.blueDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgLoanDoc" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.blue}"/>
                        <stop offset="100%" style="stop-color:${COLORS.blueDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgLoanDoc)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M18 8 L18 56 L46 56 L46 18 L36 8 Z"/>
                    <path d="M36 8 L36 18 L46 18"/>
                    <line x1="24" y1="28" x2="40" y2="28"/>
                    <line x1="24" y1="36" x2="40" y2="36"/>
                    <line x1="24" y1="44" x2="34" y2="44"/>
                </g>
                <text x="32" y="42" font-family="Arial" font-size="16" font-weight="bold" fill="${COLORS.white}" text-anchor="middle">$</text>
            </svg>`
    },

    // Collateral - shield with checkmark for asset security
    collateral: {
        name: 'collateral',
        bgColor: '#FFB300',
        bgColorDark: '#FF8F00',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgCollateral" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#FFB300"/>
                        <stop offset="100%" style="stop-color:#FF8F00"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgCollateral)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M32 8 L12 18 L12 32 Q12 48 32 56 Q52 48 52 32 L52 18 Z"/>
                    <polyline points="22,32 28,38 42,24"/>
                </g>
            </svg>`
    },

    // Vehicle - truck silhouette for vehicle category
    vehicle: {
        name: 'vehicle',
        bgColor: COLORS.gray,
        bgColorDark: COLORS.grayDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgVehicle" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.gray}"/>
                        <stop offset="100%" style="stop-color:${COLORS.grayDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgVehicle)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M8 36 L8 26 L24 26 L30 18 L48 18 L56 26 L56 36"/>
                    <line x1="8" y1="36" x2="56" y2="36"/>
                    <circle cx="18" cy="40" r="6"/>
                    <circle cx="46" cy="40" r="6"/>
                    <line x1="24" y1="40" x2="40" y2="40"/>
                </g>
            </svg>`
    },

    // Land - field/plot icon for farmland category
    land: {
        name: 'land',
        bgColor: COLORS.green,
        bgColorDark: COLORS.greenDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgLand" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.green}"/>
                        <stop offset="100%" style="stop-color:${COLORS.greenDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgLand)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M8 48 L8 20 L56 20 L56 48 Z"/>
                    <line x1="8" y1="30" x2="56" y2="30"/>
                    <line x1="8" y1="40" x2="56" y2="40"/>
                    <line x1="20" y1="20" x2="20" y2="48"/>
                    <line x1="32" y1="20" x2="32" y2="48"/>
                    <line x1="44" y1="20" x2="44" y2="48"/>
                </g>
            </svg>`
    },

    // Handshake - deal/negotiation icon
    handshake: {
        name: 'handshake',
        bgColor: COLORS.teal,
        bgColorDark: COLORS.tealDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgHandshake" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.teal}"/>
                        <stop offset="100%" style="stop-color:${COLORS.tealDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgHandshake)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M8 28 L16 20 L26 20 L32 26 L38 20 L48 20 L56 28"/>
                    <path d="M16 36 L8 28"/>
                    <path d="M48 36 L56 28"/>
                    <path d="M16 36 L26 46 L32 40 L38 46 L48 36"/>
                    <line x1="26" y1="32" x2="38" y2="32"/>
                </g>
            </svg>`
    },

    // Offer - price tag icon for bids/offers
    offer: {
        name: 'offer',
        bgColor: COLORS.orange,
        bgColorDark: COLORS.orangeDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgOffer" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.orange}"/>
                        <stop offset="100%" style="stop-color:${COLORS.orangeDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgOffer)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M50 12 L52 12 L52 14"/>
                    <path d="M52 12 L32 32"/>
                    <path d="M12 26 L12 12 L26 12 L48 34 L34 48 L12 26"/>
                    <circle cx="22" cy="22" r="4" fill="${COLORS.white}"/>
                </g>
            </svg>`
    },

    // Timer - hourglass for duration/expiration
    timer: {
        name: 'timer',
        bgColor: COLORS.blue,
        bgColorDark: COLORS.blueDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgTimer" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.blue}"/>
                        <stop offset="100%" style="stop-color:${COLORS.blueDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgTimer)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="18" y1="10" x2="46" y2="10"/>
                    <line x1="18" y1="54" x2="46" y2="54"/>
                    <path d="M20 10 L20 20 Q20 32 32 32 Q44 32 44 20 L44 10"/>
                    <path d="M20 54 L20 44 Q20 32 32 32 Q44 32 44 44 L44 54"/>
                    <line x1="32" y1="32" x2="32" y2="44"/>
                </g>
            </svg>`
    },

    // Agent - person with badge for search/sale agents
    agent: {
        name: 'agent',
        bgColor: COLORS.purple,
        bgColorDark: COLORS.purpleDark,
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgAgent" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:${COLORS.purple}"/>
                        <stop offset="100%" style="stop-color:${COLORS.purpleDark}"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgAgent)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                    <circle cx="32" cy="20" r="10"/>
                    <path d="M14 54 Q14 38 32 38 Q50 38 50 54"/>
                    <rect x="40" y="40" width="14" height="10" rx="2" fill="${COLORS.white}"/>
                </g>
            </svg>`
    },

    // Quality Star - gold star for ratings
    quality_star: {
        name: 'quality_star',
        bgColor: '#FFB300',
        bgColorDark: '#FF8F00',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgQualityStar" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#FFB300"/>
                        <stop offset="100%" style="stop-color:#FF8F00"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgQualityStar)"/>
                <polygon points="32,8 38,24 56,24 42,36 48,54 32,44 16,54 22,36 8,24 26,24"
                         fill="${COLORS.white}" stroke="${COLORS.white}" stroke-width="2" stroke-linejoin="round"/>
            </svg>`
    },

    // Lightbulb - for tips/advice sections
    lightbulb: {
        name: 'lightbulb',
        bgColor: '#FFC107',
        bgColorDark: '#FF8F00',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="bgLightbulb" x1="0%" y1="0%" x2="100%" y2="100%">
                        <stop offset="0%" style="stop-color:#FFC107"/>
                        <stop offset="100%" style="stop-color:#FF8F00"/>
                    </linearGradient>
                </defs>
                <rect width="64" height="64" rx="8" fill="url(#bgLightbulb)"/>
                <g fill="none" stroke="${COLORS.white}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M32 6 Q16 6 16 24 Q16 34 24 38 L24 48 L40 48 L40 38 Q48 34 48 24 Q48 6 32 6"/>
                    <line x1="24" y1="54" x2="40" y2="54"/>
                    <line x1="26" y1="58" x2="38" y2="58"/>
                    <line x1="32" y1="38" x2="32" y2="28"/>
                    <line x1="26" y1="32" x2="38" y2="32"/>
                </g>
            </svg>`
    },

    // v2.13.2: Star filled - solid gold star for deal ratings (transparent background)
    // Used in SaleOfferDialog to replace Unicode ★ that doesn't render in FS25 font
    star_filled: {
        name: 'star_filled',
        bgColor: 'transparent',
        bgColorDark: 'transparent',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <polygon points="32,4 40,24 62,24 44,38 50,58 32,46 14,58 20,38 2,24 24,24"
                         fill="#FFD700" stroke="#FFA000" stroke-width="1" stroke-linejoin="round"/>
            </svg>`
    },

    // v2.13.2: Star empty - dim gray outlined star for deal ratings (transparent background)
    // Used in SaleOfferDialog alongside star_filled for unfilled rating positions
    star_empty: {
        name: 'star_empty',
        bgColor: 'transparent',
        bgColorDark: 'transparent',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <polygon points="32,4 40,24 62,24 44,38 50,58 32,46 14,58 20,38 2,24 24,24"
                         fill="none" stroke="#555555" stroke-width="2" stroke-linejoin="round"/>
            </svg>`
    },

    // v2.16.0: Range marker history - gray upward arrow/triangle (transparent background)
    // Used in SaleOfferDialog BELOW range bar to show previous declined offer positions
    // Mirrors range_marker (gold ▼ above bar) but gray ▲ below bar
    range_marker_history: {
        name: 'range_marker_history',
        bgColor: 'transparent',
        bgColorDark: 'transparent',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <polygon points="32,6 6,54 58,54" fill="#888888"/>
                <polygon points="32,16 14,48 50,48" fill="#666666"/>
            </svg>`
    },

    // GMC Brand Logo - bold red "GMC" text on dark background
    // Used as brand image for the Service Truck in modDesc.xml
    brand_gmc: {
        name: 'brand_gmc',
        bgColor: '#1a1a24',
        bgColorDark: '#0f0f18',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
                <rect width="256" height="256" fill="#1a1a24"/>
                <text x="128" y="148" font-family="Arial Black, Arial" font-size="88" font-weight="900" fill="#C62828" text-anchor="middle" letter-spacing="6">GMC</text>
                <rect x="40" y="168" width="176" height="4" rx="2" fill="#C62828"/>
            </svg>`
    },

    // Range marker - yellow downward arrow/triangle (transparent background)
    // Used in SaleOfferDialog to indicate offer position on range bar
    range_marker: {
        name: 'range_marker',
        bgColor: 'transparent',
        bgColorDark: 'transparent',
        svg: (size) => `
            <svg width="${size}" height="${size}" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
                <polygon points="32,58 6,10 58,10" fill="#FFD700"/>
                <polygon points="32,48 14,16 50,16" fill="#FFA000"/>
            </svg>`
    }
};

// ============================================================
// EXPERIMENTAL: Background/Panel Assets (v2.8.0)
// ============================================================
// These are larger assets for dialog styling, not icons
// They follow the same Lua setImageFilename pattern

const BACKGROUNDS = {
    // Gradient panel background - subtle dark blue with vignette
    panel_gradient_dark: {
        name: 'panel_gradient_dark',
        width: 256,
        height: 256,
        svg: () => `
            <svg width="256" height="256" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <!-- Base gradient -->
                    <linearGradient id="panelBaseGrad" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" style="stop-color:#1a1f2a"/>
                        <stop offset="50%" style="stop-color:#141820"/>
                        <stop offset="100%" style="stop-color:#0f1218"/>
                    </linearGradient>
                    <!-- Vignette overlay -->
                    <radialGradient id="panelVignette" cx="50%" cy="50%" r="70%">
                        <stop offset="0%" style="stop-color:rgba(255,255,255,0)"/>
                        <stop offset="100%" style="stop-color:rgba(0,0,0,0.4)"/>
                    </radialGradient>
                    <!-- Subtle blue accent at top -->
                    <linearGradient id="panelAccent" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" style="stop-color:rgba(66,135,245,0.15)"/>
                        <stop offset="30%" style="stop-color:rgba(66,135,245,0)"/>
                    </linearGradient>
                </defs>
                <!-- Base fill -->
                <rect width="256" height="256" fill="url(#panelBaseGrad)"/>
                <!-- Blue accent at top -->
                <rect width="256" height="256" fill="url(#panelAccent)"/>
                <!-- Vignette effect -->
                <rect width="256" height="256" fill="url(#panelVignette)"/>
                <!-- Subtle border glow -->
                <rect x="1" y="1" width="254" height="254" fill="none"
                      stroke="rgba(100,150,255,0.1)" stroke-width="2"/>
            </svg>`
    },

    // Section header bar - horizontal gradient with glow (blue)
    header_bar_blue: {
        name: 'header_bar_blue',
        width: 512,
        height: 64,
        svg: () => `
            <svg width="512" height="64" viewBox="0 0 512 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="headerGrad" x1="0%" y1="0%" x2="100%" y2="0%">
                        <stop offset="0%" style="stop-color:#1a3a5c"/>
                        <stop offset="50%" style="stop-color:#2a4a6c"/>
                        <stop offset="100%" style="stop-color:#1a3a5c"/>
                    </linearGradient>
                    <linearGradient id="headerGlow" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" style="stop-color:rgba(100,180,255,0.3)"/>
                        <stop offset="50%" style="stop-color:rgba(100,180,255,0.1)"/>
                        <stop offset="100%" style="stop-color:rgba(100,180,255,0)"/>
                    </linearGradient>
                </defs>
                <rect width="512" height="64" fill="url(#headerGrad)"/>
                <rect width="512" height="32" fill="url(#headerGlow)"/>
                <line x1="0" y1="63" x2="512" y2="63" stroke="rgba(100,180,255,0.2)" stroke-width="1"/>
                <line x1="0" y1="1" x2="512" y2="1" stroke="rgba(150,200,255,0.15)" stroke-width="1"/>
            </svg>`
    },

    // Gold/finance themed header bar
    header_bar_gold: {
        name: 'header_bar_gold',
        width: 512,
        height: 64,
        svg: () => `
            <svg width="512" height="64" viewBox="0 0 512 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="headerGoldGrad" x1="0%" y1="0%" x2="100%" y2="0%">
                        <stop offset="0%" style="stop-color:#3d3020"/>
                        <stop offset="50%" style="stop-color:#4d4030"/>
                        <stop offset="100%" style="stop-color:#3d3020"/>
                    </linearGradient>
                    <linearGradient id="headerGoldGlow" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" style="stop-color:rgba(255,200,100,0.25)"/>
                        <stop offset="50%" style="stop-color:rgba(255,200,100,0.08)"/>
                        <stop offset="100%" style="stop-color:rgba(255,200,100,0)"/>
                    </linearGradient>
                </defs>
                <rect width="512" height="64" fill="url(#headerGoldGrad)"/>
                <rect width="512" height="32" fill="url(#headerGoldGlow)"/>
                <line x1="0" y1="63" x2="512" y2="63" stroke="rgba(255,200,100,0.2)" stroke-width="1"/>
                <line x1="0" y1="1" x2="512" y2="1" stroke="rgba(255,220,150,0.12)" stroke-width="1"/>
            </svg>`
    },

    // Green themed header bar (for credit/stats section)
    header_bar_green: {
        name: 'header_bar_green',
        width: 512,
        height: 64,
        svg: () => `
            <svg width="512" height="64" viewBox="0 0 512 64" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="headerGreenGrad" x1="0%" y1="0%" x2="100%" y2="0%">
                        <stop offset="0%" style="stop-color:#1a3d2a"/>
                        <stop offset="50%" style="stop-color:#2a4d3a"/>
                        <stop offset="100%" style="stop-color:#1a3d2a"/>
                    </linearGradient>
                    <linearGradient id="headerGreenGlow" x1="0%" y1="0%" x2="0%" y2="100%">
                        <stop offset="0%" style="stop-color:rgba(100,255,150,0.2)"/>
                        <stop offset="50%" style="stop-color:rgba(100,255,150,0.06)"/>
                        <stop offset="100%" style="stop-color:rgba(100,255,150,0)"/>
                    </linearGradient>
                </defs>
                <rect width="512" height="64" fill="url(#headerGreenGrad)"/>
                <rect width="512" height="32" fill="url(#headerGreenGlow)"/>
                <line x1="0" y1="63" x2="512" y2="63" stroke="rgba(100,255,150,0.15)" stroke-width="1"/>
                <line x1="0" y1="1" x2="512" y2="1" stroke="rgba(150,255,180,0.1)" stroke-width="1"/>
            </svg>`
    }
};

/**
 * Generate background assets (experimental)
 */
async function generateBackgrounds() {
    console.log('\nGenerating background assets (experimental)...\n');

    let success = 0;
    let failed = 0;

    for (const [key, bg] of Object.entries(BACKGROUNDS)) {
        try {
            const svgContent = bg.svg();
            const outputPath = path.join(CONFIG.outputDir, `${bg.name}.png`);

            await sharp(Buffer.from(svgContent))
                .resize(bg.width, bg.height)
                .png({ compressionLevel: 9 })
                .toFile(outputPath);

            const stats = fs.statSync(outputPath);
            console.log(`  [BG] ${bg.name}.png (${bg.width}x${bg.height}) - ${(stats.size / 1024).toFixed(1)}KB`);
            success++;
        } catch (err) {
            console.error(`  [FAIL] ${bg.name}: ${err.message}`);
            failed++;
        }
    }

    return { success, failed };
}

/**
 * Generate a single icon
 */
async function generateIcon(iconDef, outputDir) {
    const pngPath = path.join(outputDir, `${iconDef.name}.png`);
    const ddsPath = path.join(outputDir, `${iconDef.name}.dds`);

    const svgContent = iconDef.svg(CONFIG.iconSize);

    try {
        // Generate PNG
        await sharp(Buffer.from(svgContent))
            .resize(CONFIG.iconSize, CONFIG.iconSize)
            .png({ quality: 100 })
            .toFile(pngPath);

        console.log(`  [PNG] ${iconDef.name}.png`);

        // Convert to DDS if enabled and texture tool exists
        // GIANTS textureTool syntax: just pass the input file, output is auto-named .dds
        if (CONFIG.convertToDDS && fs.existsSync(CONFIG.textureTool)) {
            try {
                execSync(`"${CONFIG.textureTool}" "${pngPath}"`, {
                    stdio: 'pipe',
                    timeout: 60000
                });
                console.log(`  [DDS] ${iconDef.name}.dds`);
            } catch (err) {
                console.log(`  [WARN] DDS conversion failed for ${iconDef.name}: ${err.message}`);
            }
        }

        return true;
    } catch (err) {
        console.error(`  [ERROR] Failed to generate ${iconDef.name}: ${err.message}`);
        return false;
    }
}

/**
 * Main function
 */
async function main() {
    console.log('============================================');
    console.log('  UsedPlus Icon Generator');
    console.log('============================================');
    console.log(`  Output: ${CONFIG.outputDir}`);
    console.log(`  Size: ${CONFIG.iconSize}x${CONFIG.iconSize}`);
    console.log(`  DDS: ${CONFIG.convertToDDS ? 'Enabled' : 'Disabled'}`);
    console.log('============================================\n');

    // Ensure output directory exists
    if (!fs.existsSync(CONFIG.outputDir)) {
        fs.mkdirSync(CONFIG.outputDir, { recursive: true });
        console.log(`Created directory: ${CONFIG.outputDir}\n`);
    }

    // Check for texture tool
    if (CONFIG.convertToDDS && !fs.existsSync(CONFIG.textureTool)) {
        console.log('[WARN] GIANTS Texture Tool not found at:');
        console.log(`       ${CONFIG.textureTool}`);
        console.log('       Will generate PNG only.\n');
        CONFIG.convertToDDS = false;
    }

    // Generate all icons
    console.log('Generating icons...\n');

    let success = 0;
    let failed = 0;

    for (const [key, iconDef] of Object.entries(ICONS)) {
        if (await generateIcon(iconDef, CONFIG.outputDir)) {
            success++;
        } else {
            failed++;
        }
    }

    // Generate background assets (experimental)
    const bgResult = await generateBackgrounds();

    console.log('\n============================================');
    console.log(`  Complete! ${success} icons generated, ${failed} failed`);
    console.log(`  Backgrounds: ${bgResult.success} generated, ${bgResult.failed} failed`);
    console.log('============================================');

    // Print usage hint
    console.log('\nTo use in XML:');
    console.log('  <Bitmap profile="yourProfile" imageFilename="gui/icons/fsk_repair.dds"/>');
    console.log('\nProfile example:');
    console.log('  <Profile name="fskIconImage" extends="baseReference" with="anchorTopCenter">');
    console.log('      <size value="32px 32px"/>');
    console.log('      <imageSliceId value="noSlice"/>');
    console.log('  </Profile>');
}

main().catch(console.error);

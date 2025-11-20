#!/usr/bin/env python3
"""
Litra Glow System Tray Control
A KDE Plasma system tray application for controlling Logitech Litra Glow lights
"""

# CRITICAL: Set platform BEFORE any Qt imports
import os
import sys

# Force X11 backend for Qt - Wayland has issues with system tray popups
# This must be done before any Qt imports
os.environ['QT_QPA_PLATFORM'] = 'xcb'
print("[INFO] Forcing QT_QPA_PLATFORM=xcb (X11 compatibility layer)")

import subprocess
import signal
import traceback

# Enable verbose debugging
DEBUG = True

def debug_print(msg):
    """Print debug messages"""
    if DEBUG:
        print(f"[DEBUG] {msg}", flush=True)

from PyQt6.QtWidgets import (
    QApplication, QSystemTrayIcon, QWidget, QVBoxLayout,
    QHBoxLayout, QSlider, QLabel, QPushButton, QMessageBox, QStyleOptionSlider, QStyle
)
from PyQt6.QtCore import Qt, QTimer, QSize
from PyQt6.QtGui import QIcon, QPixmap, QPainter, QColor, QMouseEvent


class ClickJumpSlider(QSlider):
    """Custom slider that jumps to click position instead of paging"""

    def mousePressEvent(self, event: QMouseEvent):
        """Jump to the clicked position"""
        if event.button() == Qt.MouseButton.LeftButton:
            # Calculate the value based on click position
            opt = QStyleOptionSlider()
            self.initStyleOption(opt)
            groove = self.style().subControlRect(QStyle.ComplexControl.CC_Slider, opt,
                                                  QStyle.SubControl.SC_SliderGroove, self)
            handle = self.style().subControlRect(QStyle.ComplexControl.CC_Slider, opt,
                                                  QStyle.SubControl.SC_SliderHandle, self)

            if self.orientation() == Qt.Orientation.Horizontal:
                slider_length = handle.width()
                slider_min = groove.x()
                slider_max = groove.right() - slider_length + 1
                pos = event.position().x()
            else:
                slider_length = handle.height()
                slider_min = groove.y()
                slider_max = groove.bottom() - slider_length + 1
                pos = event.position().y()

            # Calculate the new value
            slider_range = slider_max - slider_min
            if slider_range > 0:
                value_range = self.maximum() - self.minimum()
                new_value = self.minimum() + ((pos - slider_min) * value_range) / slider_range
                self.setValue(int(new_value))

        super().mousePressEvent(event)


class LitraController:
    """Backend for controlling Litra devices via CLI"""

    @staticmethod
    def run_command(args):
        """Run litra command and return success status"""
        try:
            result = subprocess.run(
                ['litra'] + args,
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.returncode == 0, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return False, "", "Command timed out"
        except FileNotFoundError:
            return False, "", "litra command not found"

    @staticmethod
    def turn_on():
        """Turn on the Litra light"""
        return LitraController.run_command(['on'])

    @staticmethod
    def turn_off():
        """Turn off the Litra light"""
        return LitraController.run_command(['off'])

    @staticmethod
    def set_brightness(value):
        """Set brightness (0-100)"""
        return LitraController.run_command(['brightness', '--percentage', str(value)])

    @staticmethod
    def set_temperature(value):
        """Set color temperature (2700-6500K)"""
        return LitraController.run_command(['temperature', '--value', str(value)])

    @staticmethod
    def toggle():
        """Toggle power state"""
        return LitraController.run_command(['toggle'])


class LitraControlWidget(QWidget):
    """Popup control widget for Litra settings"""

    def __init__(self, parent=None):
        debug_print("Initializing LitraControlWidget")
        super().__init__(None)  # No parent for toplevel window

        self.setWindowTitle("Litra Glow Control")

        # Use Popup flag - this is the standard for system tray popups
        self.setWindowFlags(Qt.WindowType.Popup)
        self.resize(350, 300)

        self.is_on = False
        self.current_brightness = 50
        self.current_temperature = 4500

        # Debounce timers for sliders (apply after 500ms of no movement)
        self.brightness_timer = QTimer()
        self.brightness_timer.setSingleShot(True)
        self.brightness_timer.timeout.connect(self.apply_brightness)

        self.temperature_timer = QTimer()
        self.temperature_timer.setSingleShot(True)
        self.temperature_timer.timeout.connect(self.apply_temperature)

        self.setup_ui()
        debug_print("LitraControlWidget initialized")

    def setup_ui(self):
        """Create the control interface"""
        layout = QVBoxLayout()
        layout.setSpacing(15)
        layout.setContentsMargins(15, 15, 15, 15)

        # Title
        title = QLabel("Litra Glow Control")
        title.setStyleSheet("font-size: 16px; font-weight: bold;")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(title)

        # Power toggle button
        self.power_button = QPushButton("Turn On")
        self.power_button.setCheckable(True)
        self.power_button.setMinimumHeight(40)
        self.power_button.setStyleSheet("""
            QPushButton {
                padding: 10px;
                font-size: 14px;
                background-color: #4CAF50;
                color: white;
                border-radius: 5px;
                border: none;
            }
            QPushButton:checked {
                background-color: #f44336;
            }
            QPushButton:hover {
                opacity: 0.9;
            }
        """)
        self.power_button.clicked.connect(self.toggle_power)
        layout.addWidget(self.power_button)

        # Brightness control
        brightness_layout = QVBoxLayout()
        self.brightness_label = QLabel(f"Brightness: {self.current_brightness}%")
        self.brightness_label.setStyleSheet("font-size: 12px; font-weight: bold;")
        brightness_layout.addWidget(self.brightness_label)

        self.brightness_slider = ClickJumpSlider(Qt.Orientation.Horizontal)
        self.brightness_slider.setMinimum(0)
        self.brightness_slider.setMaximum(100)
        self.brightness_slider.setValue(self.current_brightness)
        self.brightness_slider.setTickPosition(QSlider.TickPosition.TicksBelow)
        self.brightness_slider.setTickInterval(10)
        self.brightness_slider.valueChanged.connect(self.on_brightness_changed)
        brightness_layout.addWidget(self.brightness_slider)

        layout.addLayout(brightness_layout)

        # Temperature control
        temp_layout = QVBoxLayout()
        self.temp_label = QLabel(f"Temperature: {self.current_temperature}K")
        self.temp_label.setStyleSheet("font-size: 12px; font-weight: bold;")
        temp_layout.addWidget(self.temp_label)

        self.temp_slider = ClickJumpSlider(Qt.Orientation.Horizontal)
        self.temp_slider.setMinimum(2700)
        self.temp_slider.setMaximum(6500)
        self.temp_slider.setValue(self.current_temperature)
        self.temp_slider.setTickPosition(QSlider.TickPosition.TicksBelow)
        self.temp_slider.setTickInterval(500)
        self.temp_slider.setSingleStep(100)  # Snap to 100K increments
        self.temp_slider.setPageStep(100)
        self.temp_slider.valueChanged.connect(self.on_temperature_changed)
        temp_layout.addWidget(self.temp_slider)

        # Temperature range labels
        temp_range_layout = QHBoxLayout()
        warm_label = QLabel("Warm (2700K)")
        warm_label.setStyleSheet("font-size: 10px; color: #FF9800;")
        cool_label = QLabel("Cool (6500K)")
        cool_label.setStyleSheet("font-size: 10px; color: #2196F3;")
        temp_range_layout.addWidget(warm_label)
        temp_range_layout.addStretch()
        temp_range_layout.addWidget(cool_label)
        temp_layout.addLayout(temp_range_layout)

        layout.addLayout(temp_layout)

        # Status label
        self.status_label = QLabel("Ready")
        self.status_label.setStyleSheet("font-size: 10px; color: gray;")
        self.status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self.status_label)

        self.setLayout(layout)

    def toggle_power(self):
        """Toggle light on/off"""
        if self.power_button.isChecked():
            success, stdout, stderr = LitraController.turn_on()
            if success:
                self.is_on = True
                self.power_button.setText("Turn Off")
                self.status_label.setText("Light is ON")
                self.status_label.setStyleSheet("font-size: 10px; color: green;")
                # Apply current settings
                LitraController.set_brightness(self.current_brightness)
                LitraController.set_temperature(self.current_temperature)
            else:
                self.power_button.setChecked(False)
                self.show_error(f"Failed to turn on: {stderr}")
        else:
            success, stdout, stderr = LitraController.turn_off()
            if success:
                self.is_on = False
                self.power_button.setText("Turn On")
                self.status_label.setText("Light is OFF")
                self.status_label.setStyleSheet("font-size: 10px; color: red;")
            else:
                self.power_button.setChecked(True)
                self.show_error(f"Failed to turn off: {stderr}")

    def on_brightness_changed(self, value):
        """Handle brightness slider change"""
        self.current_brightness = value
        self.brightness_label.setText(f"Brightness: {value}%")

        # Restart the debounce timer (will apply after 500ms of no changes)
        if self.is_on:
            self.brightness_timer.stop()
            self.brightness_timer.start(500)  # 500ms debounce

    def on_temperature_changed(self, value):
        """Handle temperature slider change"""
        # Round to nearest 100K for display (hardware requirement)
        rounded_value = round(value / 100) * 100
        self.current_temperature = rounded_value
        self.temp_label.setText(f"Temperature: {rounded_value}K")

        # Restart the debounce timer (will apply after 500ms of no changes)
        if self.is_on:
            self.temperature_timer.stop()
            self.temperature_timer.start(500)  # 500ms debounce

    def apply_brightness(self):
        """Actually apply brightness to device (called after debounce)"""
        debug_print(f"Applying brightness: {self.current_brightness}%")
        success, stdout, stderr = LitraController.set_brightness(self.current_brightness)
        if not success:
            debug_print(f"Failed to set brightness: {stderr}")
            self.status_label.setText(f"Brightness failed")
            self.status_label.setStyleSheet("font-size: 10px; color: orange;")
        else:
            self.status_label.setText(f"Brightness: {self.current_brightness}%")
            self.status_label.setStyleSheet("font-size: 10px; color: green;")

    def apply_temperature(self):
        """Actually apply temperature to device (called after debounce)"""
        # Temperature is already rounded in on_temperature_changed
        debug_print(f"Applying temperature: {self.current_temperature}K")
        success, stdout, stderr = LitraController.set_temperature(self.current_temperature)
        if not success:
            debug_print(f"Failed to set temperature: {stderr}")
            self.status_label.setText(f"Temperature failed")
            self.status_label.setStyleSheet("font-size: 10px; color: orange;")
        else:
            self.status_label.setText(f"Temperature: {self.current_temperature}K")
            self.status_label.setStyleSheet("font-size: 10px; color: green;")

    def show_error(self, message):
        """Show error message"""
        QMessageBox.critical(self, "Litra Control Error", message)


class LitraSystemTray(QSystemTrayIcon):
    """System tray icon and menu for Litra control"""

    @staticmethod
    def create_icon():
        """Create a tray icon with fallback"""
        # Try common icon theme names
        for icon_name in ["light-bulb", "brightness-high", "weather-clear"]:
            icon = QIcon.fromTheme(icon_name)
            if not icon.isNull():
                return icon

        # Fallback: create a simple light bulb icon
        pixmap = QPixmap(64, 64)
        pixmap.fill(Qt.GlobalColor.transparent)

        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Draw a simple light bulb shape
        painter.setBrush(QColor(255, 220, 100))  # Warm yellow
        painter.setPen(QColor(100, 100, 100))
        painter.drawEllipse(16, 12, 32, 32)  # Bulb
        painter.drawRect(24, 44, 16, 8)      # Base

        painter.end()

        return QIcon(pixmap)

    def __init__(self, parent=None):
        debug_print("Initializing LitraSystemTray")
        super().__init__(parent)

        # Set icon with fallback
        self.setIcon(self.create_icon())
        self.setToolTip("Litra Glow Control\nLeft-click: Controls\nRight-click: Quit")

        # Handle tray icon clicks
        self.activated.connect(self.on_tray_activated)

        # Create control widget (but don't show it yet)
        self.control_widget = LitraControlWidget()

        # Store the click position
        self.click_pos = None

        # Show the tray icon
        self.show()

        debug_print("LitraSystemTray initialized")

    def on_tray_activated(self, reason):
        """Handle tray icon activation"""
        debug_print(f"Tray activated with reason: {reason}")

        # Capture cursor position immediately when tray is clicked
        from PyQt6.QtGui import QCursor
        self.click_pos = QCursor.pos()
        debug_print(f"Click position captured: ({self.click_pos.x()}, {self.click_pos.y()})")

        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            # Left click - show control widget
            debug_print("Left click detected")
            self.show_control_widget()
        elif reason == QSystemTrayIcon.ActivationReason.Context:
            # Right click - quit
            debug_print("Right click detected - quitting")
            QApplication.quit()

    def show_control_widget(self):
        """Show or toggle the control widget"""
        debug_print("show_control_widget called")

        if self.control_widget.isVisible():
            debug_print("Hiding control widget")
            self.control_widget.hide()
        else:
            debug_print("Showing control widget")

            # Use QSystemTrayIcon::geometry() to position near icon
            icon_geometry = self.geometry()
            debug_print(f"Tray icon geometry: {icon_geometry}")

            if icon_geometry.isValid() and icon_geometry.x() != 0 and icon_geometry.y() != 0:
                # Position below the icon
                x = icon_geometry.x()
                y = icon_geometry.y() + icon_geometry.height() + 5
                debug_print(f"Using icon geometry, positioning at: ({x}, {y})")
                self.control_widget.move(x, y)
            else:
                # Fallback: Use click position captured in on_tray_activated
                if self.click_pos is None:
                    # Shouldn't happen, but fallback to current cursor position
                    from PyQt6.QtGui import QCursor
                    self.click_pos = QCursor.pos()

                debug_print(f"Invalid geometry, using captured click position: ({self.click_pos.x()}, {self.click_pos.y()})")

                # ALWAYS use the ASUS monitor (middle landscape monitor)
                # Find it by looking for the 1707x960 screen starting at x=1440
                asus_screen = None
                for screen in QApplication.screens():
                    geom = screen.geometry()
                    debug_print(f"Checking screen: {geom}")
                    # ASUS monitor is 1707x960 at position (1440, 259)
                    if geom.width() == 1707 and geom.height() == 960:
                        asus_screen = screen
                        debug_print(f"Found ASUS monitor: {geom}")
                        break

                # Fallback to screen at click position if ASUS not found
                if asus_screen is None:
                    debug_print("ASUS monitor not found, using screen at click position")
                    asus_screen = QApplication.screenAt(self.click_pos)
                    if asus_screen is None:
                        asus_screen = QApplication.primaryScreen()

                screen_geometry = asus_screen.geometry()
                debug_print(f"Target screen geometry: {screen_geometry}")

                # Position popup at top-right of ASUS monitor (near typical tray location)
                # Place it near the top-right corner with some padding
                x = screen_geometry.right() - self.control_widget.width() - 20
                y = screen_geometry.top() + 50  # Below the top edge

                debug_print(f"Final position: ({x}, {y}) on ASUS monitor")
                self.control_widget.move(x, y)

            self.control_widget.show()
            self.control_widget.raise_()
            self.control_widget.activateWindow()
            debug_print("Control widget shown")


def main():
    """Main application entry point"""
    debug_print("Starting Litra Tray application")

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    debug_print(f"Platform: {app.platformName()}")

    # Check if litra command is available
    success, stdout, stderr = LitraController.run_command(['--version'])
    if not success:
        debug_print(f"litra command not found: {stderr}")
        QMessageBox.critical(
            None,
            "Litra Command Not Found",
            "The 'litra' command is not available.\n\n"
            "Please ensure the litra CLI tool is installed."
        )
        sys.exit(1)

    debug_print(f"litra version: {stdout.strip()}")

    # Create system tray
    tray = LitraSystemTray()

    # Cleanup function
    def cleanup():
        """Clean up tray icon before exit"""
        debug_print("Cleanup called")
        tray.hide()

    app.aboutToQuit.connect(cleanup)

    # Handle Ctrl+C gracefully
    def signal_handler(signum, frame):
        """Handle SIGINT and SIGTERM"""
        debug_print(f"Signal {signum} received")
        print("\nShutting down gracefully...")
        app.quit()

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Make Python check for signals periodically
    timer = QTimer()
    timer.timeout.connect(lambda: None)
    timer.start(500)

    debug_print("Entering event loop")
    sys.exit(app.exec())


if __name__ == '__main__':
    main()

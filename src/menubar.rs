#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use eframe::egui;
use litra::{DeviceHandle, Litra};
use std::sync::{Arc, Mutex};
use tray_icon::menu::MenuEvent;
use tray_icon::{TrayIconBuilder, TrayIconEvent, MouseButton, MouseButtonState};

/// Application state shared between UI and background tasks
struct AppState {
    context: Litra,
    selected_device_index: Option<usize>,
    power_on: bool,
    brightness: u16,
    temperature: u16,
    error_message: Option<String>,
}

impl Default for AppState {
    fn default() -> Self {
        let context = Litra::new().unwrap_or_else(|e| {
            eprintln!("Failed to initialize Litra: {}", e);
            panic!("Cannot continue without Litra context");
        });

        Self {
            context,
            selected_device_index: Some(0),
            power_on: false,
            brightness: 100,
            temperature: 4000,
            error_message: None,
        }
    }
}

impl AppState {
    /// Get the currently selected device handle
    fn get_device_handle(&self) -> Option<DeviceHandle> {
        if let Some(index) = self.selected_device_index {
            let device = self.context.get_connected_devices().nth(index)?;
            device.open(&self.context).ok()
        } else {
            None
        }
    }

    /// Refresh device state from hardware
    fn refresh_from_device(&mut self) {
        if let Some(handle) = self.get_device_handle() {
            match handle.is_on() {
                Ok(is_on) => self.power_on = is_on,
                Err(e) => self.error_message = Some(format!("Failed to read power state: {}", e)),
            }

            if self.power_on {
                match handle.brightness_in_lumen() {
                    Ok(brightness) => self.brightness = brightness,
                    Err(e) => self.error_message = Some(format!("Failed to read brightness: {}", e)),
                }

                match handle.temperature_in_kelvin() {
                    Ok(temp) => self.temperature = temp,
                    Err(e) => self.error_message = Some(format!("Failed to read temperature: {}", e)),
                }
            }
        }
    }

    /// Apply current state to device
    fn apply_to_device(&mut self) {
        if let Some(handle) = self.get_device_handle() {
            // Set power state
            if let Err(e) = handle.set_on(self.power_on) {
                self.error_message = Some(format!("Failed to set power: {}", e));
                return;
            }

            if self.power_on {
                // Set brightness
                if let Err(e) = handle.set_brightness_in_lumen(self.brightness) {
                    self.error_message = Some(format!("Failed to set brightness: {}", e));
                }

                // Round temperature to nearest 100
                let rounded_temp = (self.temperature / 100) * 100;
                if let Err(e) = handle.set_temperature_in_kelvin(rounded_temp) {
                    self.error_message = Some(format!("Failed to set temperature: {}", e));
                }
            }

            self.error_message = None;
        } else {
            self.error_message = Some("No device selected or device not found".to_string());
        }
    }
}

/// The egui application
struct LitraMenuBarApp {
    state: Arc<Mutex<AppState>>,
    visible: Arc<Mutex<bool>>,
    tray_icon: Option<tray_icon::TrayIcon>,
    initialized: bool,
}

impl LitraMenuBarApp {
    fn new(state: Arc<Mutex<AppState>>, visible: Arc<Mutex<bool>>) -> Self {
        Self {
            state,
            visible,
            tray_icon: None,
            initialized: false,
        }
    }
}

impl eframe::App for LitraMenuBarApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Initialize tray icon on first frame
        if !self.initialized {
            self.initialized = true;

            // Create tray icon without menu first
            let icon_data = create_icon_data();
            self.tray_icon = TrayIconBuilder::new()
                .with_tooltip("Litra Control")
                .with_icon(icon_data)
                .build()
                .ok();
        }

        // Handle tray icon events
        if let Ok(event) = TrayIconEvent::receiver().try_recv() {
            eprintln!("DEBUG: Got tray event: {:?}", event);
            match event {
                TrayIconEvent::Click { button, button_state, rect, .. } => {
                    eprintln!("DEBUG: Click event - button: {:?}, state: {:?}, rect: {:?}", button, button_state, rect);
                    if button == MouseButton::Left && button_state == MouseButtonState::Up {
                        // Toggle window visibility on left click
                        let mut vis = self.visible.lock().unwrap();
                        let old_vis = *vis;
                        *vis = !*vis;
                        eprintln!("DEBUG: Toggling visibility from {} to {}", old_vis, *vis);
                        if *vis {
                            // Position window below the menu bar icon, centered under it
                            // Get the scale factor for retina displays
                            let scale_factor = ctx.input(|i| i.viewport().native_pixels_per_point.unwrap_or(2.0));

                            // Convert physical pixels to logical pixels
                            let icon_x = rect.position.x as f32 / scale_factor;
                            let icon_y = rect.position.y as f32 / scale_factor;
                            let icon_width = rect.size.width as f32 / scale_factor;
                            let icon_height = rect.size.height as f32 / scale_factor;

                            let icon_center_x = icon_x + (icon_width / 2.0);
                            let window_width = 350.0;
                            let x = icon_center_x - (window_width / 2.0); // Center window under icon
                            let y = icon_y + icon_height; // Just below the icon

                            eprintln!("DEBUG: Scale factor: {}", scale_factor);
                            eprintln!("DEBUG: Icon rect (physical) - x={}, y={}, width={}, height={}", rect.position.x, rect.position.y, rect.size.width, rect.size.height);
                            eprintln!("DEBUG: Icon rect (logical) - x={}, y={}, width={}, height={}", icon_x, icon_y, icon_width, icon_height);
                            eprintln!("DEBUG: Positioning window at x={}, y={} (icon_center={}, window_width={})", x, y, icon_center_x, window_width);
                            ctx.send_viewport_cmd(egui::ViewportCommand::OuterPosition(egui::Pos2::new(x, y)));
                            ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
                        }
                    }
                }
                _ => {
                    eprintln!("DEBUG: Other event type");
                }
            }
        }

        // Handle menu events
        if let Ok(_event) = MenuEvent::receiver().try_recv() {
            // Quit menu item clicked
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }

        // Check if window should be visible
        let should_be_visible = *self.visible.lock().unwrap();
        eprintln!("DEBUG: Window should_be_visible = {}", should_be_visible);

        if should_be_visible {
            eprintln!("DEBUG: Sending Visible(true) command");
            ctx.send_viewport_cmd(egui::ViewportCommand::Visible(true));
        } else {
            eprintln!("DEBUG: Sending Visible(false) command, returning early");
            ctx.send_viewport_cmd(egui::ViewportCommand::Visible(false));
            return;
        }

        eprintln!("DEBUG: Drawing UI");
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("Litra Control");
            ui.separator();

            let mut state = self.state.lock().unwrap();

            // Device selection - collect device info separately to avoid borrow issues
            let device_info: Vec<(String, String)> = state.context.get_connected_devices()
                .map(|d| (d.device_type().to_string(), d.device_path().chars().take(20).collect()))
                .collect();

            if device_info.is_empty() {
                ui.colored_label(egui::Color32::RED, "No Litra devices found!");
                return;
            }

            ui.horizontal(|ui| {
                ui.label("Device:");
                egui::ComboBox::from_id_salt("device_selector")
                    .selected_text(
                        if let Some(index) = state.selected_device_index {
                            if let Some((dtype, path)) = device_info.get(index) {
                                format!("{} ({})", dtype, path)
                            } else {
                                "Select device...".to_string()
                            }
                        } else {
                            "Select device...".to_string()
                        }
                    )
                    .show_ui(ui, |ui| {
                        for (i, (dtype, path)) in device_info.iter().enumerate() {
                            let label = format!("{} ({})", dtype, path);
                            if ui.selectable_label(state.selected_device_index == Some(i), label).clicked() {
                                state.selected_device_index = Some(i);
                                state.refresh_from_device();
                            }
                        }
                    });
            });

            ui.separator();

            // Refresh button
            if ui.button("Refresh State").clicked() {
                state.refresh_from_device();
            }

            ui.separator();

            // Power toggle
            let mut power_changed = false;
            if ui.checkbox(&mut state.power_on, "Power").changed() {
                power_changed = true;
            }

            ui.separator();

            // Brightness control
            if state.power_on {
                ui.label("Brightness (lumen):");

                let (min_brightness, max_brightness) = if let Some(handle) = state.get_device_handle() {
                    (handle.minimum_brightness_in_lumen(), handle.maximum_brightness_in_lumen())
                } else {
                    (20, 400)
                };

                if ui.add(egui::Slider::new(&mut state.brightness, min_brightness..=max_brightness)).changed() {
                    // Apply brightness change in real-time
                    if let Some(handle) = state.get_device_handle() {
                        let _ = handle.set_brightness_in_lumen(state.brightness);
                    }
                }

                ui.separator();

                // Temperature control
                ui.label("Temperature (Kelvin):");
                if ui.add(egui::Slider::new(&mut state.temperature, 2700..=6500)
                    .step_by(100.0)).changed() {
                    // Apply temperature change in real-time
                    if let Some(handle) = state.get_device_handle() {
                        let rounded_temp = (state.temperature / 100) * 100;
                        let _ = handle.set_temperature_in_kelvin(rounded_temp);
                    }
                }
            }

            // Apply changes
            if power_changed {
                state.apply_to_device();
            }

            ui.separator();

            // Quit button at the bottom
            if ui.button("Quit").clicked() {
                ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            }

            // Show errors
            if let Some(ref error) = state.error_message {
                ui.separator();
                ui.colored_label(egui::Color32::RED, error);
            }
        });

        // Handle Cmd+Q to quit
        if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::Q)) {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Create application state
    let state = Arc::new(Mutex::new(AppState::default()));

    // Initialize state from first device
    {
        let mut state_lock = state.lock().unwrap();
        state_lock.refresh_from_device();
    }

    let state_clone = Arc::clone(&state);
    let visible = Arc::new(Mutex::new(false)); // Start hidden

    // Run egui app
    let native_options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([350.0, 450.0])
            .with_resizable(false)
            .with_decorations(false) // No window decorations for menu bar style
            .with_visible(false) // Start hidden
            .with_always_on_top(),
        ..Default::default()
    };

    eframe::run_native(
        "Litra Control",
        native_options,
        Box::new(move |_cc| Ok(Box::new(LitraMenuBarApp::new(state_clone, visible)))),
    )?;

    Ok(())
}

/// Create a simple icon for the system tray
fn create_icon_data() -> tray_icon::Icon {
    // Create a simple 32x32 icon (light bulb shape)
    let size = 32;
    let mut rgba = vec![0u8; size * size * 4];

    // Draw a simple circle (light bulb representation)
    for y in 0..size {
        for x in 0..size {
            let dx = x as i32 - size as i32 / 2;
            let dy = y as i32 - size as i32 / 2;
            let dist_sq = dx * dx + dy * dy;
            let radius_sq = (size as i32 / 3) * (size as i32 / 3);

            let idx = (y * size + x) * 4;
            if dist_sq <= radius_sq {
                // Yellow circle
                rgba[idx] = 255;     // R
                rgba[idx + 1] = 255; // G
                rgba[idx + 2] = 0;   // B
                rgba[idx + 3] = 255; // A
            } else {
                // Transparent background
                rgba[idx + 3] = 0;
            }
        }
    }

    tray_icon::Icon::from_rgba(rgba, size as u32, size as u32)
        .expect("Failed to create icon")
}

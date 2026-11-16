#pragma once
#include "core/module.h"
#include "core/face.h"

// Modul utama: wajah Lokana dengan ekspresi, mood, dan reaksi colekan.
class FaceModule : public Module {
public:
  const char* name() const override { return "Lokana"; }
  void enter() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  Face& face() { return _face; }

private:
  void pickIdle(uint32_t now);
  Expression baseline(uint32_t now) const;
  Face _face;
  bool _started = false;
  uint32_t _lastPoke = 0, _pokeWindow = 0, _nextIdle = 0, _lastTouch = 0;
  uint8_t _pokes = 0;
};

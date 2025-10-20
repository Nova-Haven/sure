// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";
import "viewport_init";

Turbo.StreamActions.redirect = function () {
  Turbo.visit(this.target);
};

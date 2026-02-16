import { route, routeParams, isTabRoute, navigate, initRouter } from './router';

describe('router', () => {
  beforeEach(() => {
    // Reset state
    window.location.hash = '';
    route.value = 'home';
    routeParams.value = {};
  });

  describe('initRouter + hash parsing', () => {
    it('parses #/home to route "home"', () => {
      window.location.hash = '#/home';
      initRouter();
      expect(route.value).toBe('home');
    });

    it('parses #/program to route "program"', () => {
      window.location.hash = '#/program';
      initRouter();
      expect(route.value).toBe('program');
    });

    it('parses #/session to route "session"', () => {
      window.location.hash = '#/session';
      initRouter();
      expect(route.value).toBe('session');
    });

    it('defaults empty hash to "home"', () => {
      window.location.hash = '';
      initRouter();
      expect(route.value).toBe('home');
    });

    it('defaults unknown route to "home"', () => {
      window.location.hash = '#/nonexistent';
      initRouter();
      expect(route.value).toBe('home');
    });

    it('parses route params from hash', () => {
      window.location.hash = '#/session/id/123';
      initRouter();
      expect(route.value).toBe('session');
      expect(routeParams.value).toEqual({ id: '123' });
    });
  });

  describe('navigate', () => {
    it('sets hash for simple route', () => {
      navigate('program');
      expect(window.location.hash).toBe('#/program');
    });

    it('sets hash with params', () => {
      navigate('session', { id: '456' });
      expect(window.location.hash).toBe('#/session/id/456');
    });
  });

  describe('isTabRoute', () => {
    it('returns true for home', () => {
      route.value = 'home';
      expect(isTabRoute.value).toBe(true);
    });

    it('returns true for program', () => {
      route.value = 'program';
      expect(isTabRoute.value).toBe(true);
    });

    it('returns true for history', () => {
      route.value = 'history';
      expect(isTabRoute.value).toBe(true);
    });

    it('returns true for profile', () => {
      route.value = 'profile';
      expect(isTabRoute.value).toBe(true);
    });

    it('returns false for session', () => {
      route.value = 'session';
      expect(isTabRoute.value).toBe(false);
    });

    it('returns false for onboarding', () => {
      route.value = 'onboarding';
      expect(isTabRoute.value).toBe(false);
    });
  });
});

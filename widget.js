
const RANKS = [
  ...generateRanks('Bronze', 5, 'assets/uploads/bronze'),
  ...generateRanks('Silver', 5, 'assets/uploads/silver'),
  ...generateRanks('Gold', 5, 'assets/uploads/gold'),
  ...generateRanks('Platinum', 5, 'assets/uploads/platinum'),
  ...generateRanks('Diamond', 5, 'assets/uploads/diamond'),
  ...generateRanks('Master', 5, 'assets/uploads/master'),
  ...generateRanks('Grandmaster', 5, 'assets/uploads/grandmaster'),
  ...generateRanks('Champion', 5, 'assets/uploads/champion'),

  ...Array.from({ length: 500 }, (_, i) => ({
    type: 'Top',
    level: 500 - i, 
    img: 'assets/uploads/top_500.png'
  }))
];

function generateRanks(type, levels, imgPrefix) {
  return Array.from({ length: levels }, (_, i) => ({ type: type, level: levels - i, img: `${imgPrefix}.png` }));
}

document.addEventListener('DOMContentLoaded', () => {
  const LOCAL_STORAGE_KEY = 'widget_previous_state';

  const dom = {
    widget: document.getElementById('widget'),
    wins: document.getElementById('wins'),
    losses: document.getElementById('losses'),
    winsIconContainer: document.getElementById('winsIconContainer'),
    lossesIconContainer: document.getElementById('lossesIconContainer'),
    winsFillGradient: document.getElementById('winsFillGradient'),
    lossesFillGradient: document.getElementById('lossesFillGradient'),
    rankAnimationWrapper: document.getElementById('rank-animation-wrapper'),
    rankImage: document.getElementById('rankImage'),
    rankValue: document.getElementById('rankValue'),
  };

  const fillLimit = 10;
  let isRankTransitionAnimating = false; 
  let hideWidgetTimeout;
  let reappearTimeout;

  const params = new URLSearchParams(window.location.search);

  const animDurationIn = parseFloat(params.get('animDurationIn')) / 1000 || 0.5;
  const animStayTime = parseFloat(params.get('animStayTime')) / 1000 || 10;
  const animDurationOut = parseFloat(params.get('animDurationOut')) / 1000 || 0.5;
  const reappearDelayMs = parseFloat(params.get('hiddenTime')) || 0;
  const animDirection = params.get('animDirection') || 'left';
  const animationTimingFunction = params.get('animationTimingFunction') || 'cubic-bezier(0.25, 1, 0.5, 1)';

  document.documentElement.style.setProperty('--bg-color', decodeURIComponent(params.get('bgColor') || 'rgba(0,0,0,0.7)'));
  document.documentElement.style.setProperty('--wins-color', decodeURIComponent(params.get('winsColor') || '#00ff00'));
  document.documentElement.style.setProperty('--losses-color', decodeURIComponent(params.get('lossesColor') || '#ff0000'));
  document.documentElement.style.setProperty('--rank-text-color', decodeURIComponent(params.get('rankTextColor') || '#ffffff'));
  document.documentElement.style.setProperty('--font', decodeURIComponent(params.get('font') || 'Arial, sans-serif'));
  document.documentElement.style.setProperty('--font-size', decodeURIComponent(params.get('fontSize') + 'px' || '16px'));
  document.documentElement.style.setProperty('--animation-duration-in', `${animDurationIn}s`);
  document.documentElement.style.setProperty('--animation-duration-out', `${animDurationOut}s`);
  document.documentElement.style.setProperty('--animation-timing-function', animationTimingFunction);
  dom.widget.style.background = params.get('bgImage') ? `url('${decodeURIComponent(params.get('bgImage'))}') center/cover no-repeat` : decodeURIComponent(params.get('bgColor') || 'rgba(0,0,0,0.7)');

  // Функция для получения абсолютного индекса ранга в массиве RANKS
  function getAbsoluteRankIndex(rankData) {
    
      if (typeof rankData === 'number') {
          const index = Math.max(0, Math.min(rankData, RANKS.length - 1));
          return index;
      }      
      else if (rankData && typeof rankData.rankIndex !== 'undefined' && typeof rankData.rankLevel !== 'undefined') {
          let index = -1;          
          if (rankData.rankIndex >= 0 && rankData.rankIndex <= 7) { // Bronze (0) to Champion (7)
              index = (rankData.rankIndex * 5) + (5 - rankData.rankLevel);
          } else if (rankData.rankIndex === 8) { // Top 500
              const baseIndexForTop500 = (8 * 5); // 8 types (Bronze-Champion) * 5 levels each
              index = baseIndexForTop500 + (500 - rankData.rankLevel); // rankLevel for Top 500 is 500 down to 1
          }
          const finalIndex = Math.max(0, Math.min(index, RANKS.length - 1));
          return finalIndex;
      }
      return -1;
  }

  // Функция для получения информации о ранге по абсолютному индексу
  function getRankInfo(absoluteRankIndex) {
    if (absoluteRankIndex === -1 || absoluteRankIndex >= RANKS.length || !RANKS[absoluteRankIndex]) {
        return { type: 'Unranked', level: 0, img: 'assets/uploads/unranked.png', display: 'Unranked' };
    }
    const rank = RANKS[absoluteRankIndex];
    if (rank) {
        if (rank.type === 'Top') {
            return { ...rank, display: `#${rank.level}` };
        } else {
            return { ...rank, display: `${rank.type} ${rank.level}` };
        }
    }
    return { type: 'Unranked', level: 0, img: 'assets/uploads/unranked.png', display: 'Unranked' };
  }

  // --- 2. Функции для управления визуализацией и анимациями ---

  function setGradientFill(gradientElement, value) {
      const stop1 = gradientElement.querySelector('.gradient-stop-1');
      const stop2 = gradientElement.querySelector('.gradient-stop-2');
      if (!stop1 || !stop2) {
          console.error("Gradient stops not found for:", gradientElement.id);
          return;
      }
      const fillPercent = (value % fillLimit) / fillLimit;
      stop1.setAttribute('offset', fillPercent);
      stop2.setAttribute('offset', fillPercent);
  }

  function animateNumber(element, from, to) {
    if (from === to) return;
    let isReset = to < from;
    const duration = isReset ? 750 : 500;
    let start = null;
    element.classList.add('value-change');
    element.textContent = from;
    function step(timestamp) {
        if (!start) start = timestamp;
        const progress = Math.min((timestamp - start) / duration, 1);
        if (isReset) {
            element.textContent = Math.max(0, Math.round(from - progress * (from - to)));
        } else {
            element.textContent = Math.round(from + progress * (to - from));
        }
        if (progress < 1) {
            requestAnimationFrame(step);
        } else {
            element.textContent = to;
            setTimeout(() => element.classList.remove('value-change'), 500);
        }
    }
    requestAnimationFrame(step);
  }

  function animateFill(gradientElement, iconContainer, from, to) {
      if (from === to) {
          setGradientFill(gradientElement, to);
          return;
      }
      setGradientFill(gradientElement, from);
      setTimeout(() => {
          setGradientFill(gradientElement, to);
          if (to > from && to > 0 && to % fillLimit === 0) {
              setTimeout(() => {
                  setGradientFill(gradientElement, 10);
                  const resetClass = iconContainer.id.includes('losses') ? 'skull-shake-active' : 'fanfare-active';
                  iconContainer.classList.add(resetClass);
                  setTimeout(() => {
                      setGradientFill(gradientElement, 0);
                      iconContainer.classList.remove(resetClass);
                  }, 2000);
              }, 500);
          }
      }, 100);
  }

  function animateRankTransition(fromAbsoluteIndex, toAbsoluteIndex) {
      if (isRankTransitionAnimating) {
          console.warn(`[animateRankTransition] Skipping animation. Already animating.`);
          return;
      }
      isRankTransitionAnimating = true;

      dom.rankAnimationWrapper.classList.remove('rank-up-division', 'rank-down-division', 'rank-level-change', 'rank-idle-pulse');
      
      const fromRankInfo = getRankInfo(fromAbsoluteIndex);
      const toRankInfo = getRankInfo(toAbsoluteIndex);
      
      console.log(`[animateRankTransition] Starting. From: ${fromRankInfo.display} (abs:${fromAbsoluteIndex}) to: ${toRankInfo.display} (abs:${toAbsoluteIndex})`);

      let animationClass = '';
      let animationDuration = 0;

      const isRankUp = (toAbsoluteIndex > fromAbsoluteIndex);
      const isDivisionChange = (fromRankInfo.type !== toRankInfo.type);

      if (isRankUp) { // Rank Up
          if (isDivisionChange) { // e.g., Platinum 1 -> Diamond 5 (different type)
              animationClass = 'rank-up-division';
              animationDuration = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--rank-epic-duration')) * 1000;
          } else { // e.g., Gold 4 -> Gold 3 (same type, just level changes)
              animationClass = 'rank-level-change';
              animationDuration = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--rank-subtle-duration')) * 1000;
          }
      } else { // Rank Down (or no change but previous was higher for some reason)
          if (isDivisionChange) { // e.g., Diamond 5 -> Platinum 1 (different type)
              animationClass = 'rank-down-division';
              animationDuration = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--rank-epic-duration')) * 1000;
          } else { // e.g., Gold 3 -> Gold 4 (same type, level changes)
              animationClass = 'rank-level-change';
              animationDuration = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--rank-subtle-duration')) * 1000;
          }
      }
      
      console.log(`[animateRankTransition] Chosen animationClass = ${animationClass}, Duration = ${animationDuration}ms`);

      dom.rankImage.src = fromRankInfo.img;
      dom.rankValue.textContent = fromRankInfo.display;
      dom.rankAnimationWrapper.classList.add(animationClass);

      setTimeout(() => {
          dom.rankImage.src = toRankInfo.img;
          dom.rankValue.textContent = toRankInfo.display;
      }, animationDuration / 2); 

      setTimeout(() => {
          dom.rankAnimationWrapper.classList.remove(animationClass);
          isRankTransitionAnimating = false;
          console.log(`[animateRankTransition] Animation ${animationClass} finished. isRankTransitionAnimating set to false.`);         

          if (dom.widget.classList.contains('visible')) {
              console.log(`[animateRankTransition] Applying rank-idle-pulse after transition completion.`);
              dom.rankAnimationWrapper.classList.add('rank-idle-pulse');
          }
          previousState.rank = currentState.rank
      }, animationDuration + 50); 
     
  }

  function showWidgetAndAnimateContent() {
    clearTimeout(hideWidgetTimeout);
    clearTimeout(reappearTimeout);

    dom.widget.classList.remove('hide', 'from-left', 'from-right', 'from-top', 'from-bottom');
    dom.widget.classList.add(`from-${animDirection}`);
    dom.widget.classList.remove('visible');
    dom.rankAnimationWrapper.classList.remove('rank-up-division', 'rank-down-division', 'rank-level-change', 'rank-idle-pulse');
    setTimeout(() => {
      dom.widget.classList.add('visible');
      const currentRankInfo = getRankInfo(currentState.rank);
      dom.rankImage.src = currentRankInfo.img;
      dom.rankValue.textContent = currentRankInfo.display;
      const shouldAnimateRankTransition = (previousState.rank !== currentState.rank);
      console.log(`[showWidgetAndAnimateContent] previousState.rank=${previousState.rank} (${getRankInfo(previousState.rank).display}), currentState.rank=${currentState.rank} (${getRankInfo(currentState.rank).display}), shouldAnimateRankTransition=${shouldAnimateRankTransition}`);
      if (shouldAnimateRankTransition) {
          console.log(`[showWidgetAndAnimateContent] Calling animateRankTransition due to rank change.`);
          animateRankTransition(previousState.rank, currentState.rank);
      } else {
          console.log(`[showWidgetAndAnimateContent] Rank NOT changed. Applying idle pulse.`);
          dom.rankAnimationWrapper.classList.add('rank-idle-pulse');
      }
      animateNumber(dom.wins, previousState.wins, currentState.wins);
      animateNumber(dom.losses, previousState.losses, currentState.losses);
      animateFill(dom.winsFillGradient, dom.winsIconContainer, previousState.wins, currentState.wins);
      animateFill(dom.lossesFillGradient, dom.lossesIconContainer, previousState.losses, currentState.losses);
      
      if (animStayTime > 0) {
          hideWidgetTimeout = setTimeout(() => {
              dom.widget.classList.remove('visible');
              dom.widget.classList.add('hide', `from-${animDirection}`);
              dom.rankAnimationWrapper.classList.remove('rank-idle-pulse'); 
              
              if (reappearDelayMs > 0) {
                  reappearTimeout = setTimeout(() => {
                      showWidgetAndAnimateContent();
                  }, (animDurationOut * 1000) + reappearDelayMs);
              }
          }, animStayTime * 1000);
      }
    }, (animDurationIn * 1000) + 50); 
  }
  let previousState = null;
  try {
      const storedState = localStorage.getItem(LOCAL_STORAGE_KEY);
      if (storedState) {
          previousState = JSON.parse(storedState);
      }
  } catch (e) {
      console.warn('Could not parse previous state from localStorage.', e);
  }

  let initialCurrentState = {
      wins: parseInt(params.get('wins'), 10) || 0,
      losses: parseInt(params.get('losses'), 10) || 0,
      rank: getAbsoluteRankIndex(parseInt(params.get('rank'), 10) || 0),
  };

  let currentState = { ...initialCurrentState }; // current state that will be used for display

  if (!previousState || typeof previousState.rank === 'undefined' || previousState.rank === -1) {
      console.log("[INIT] No valid previous state found in localStorage. Setting previousState = currentState.");
      previousState = { ...currentState };
  } else {
      if (typeof previousState.rank !== 'number' || previousState.rank === -1) {
          previousState.rank = getAbsoluteRankIndex(previousState.rank);
          console.warn(`[INIT] Converted previousState.rank from non-number to absolute index: ${previousState.rank}`);
      }
      if (previousState.wins === currentState.wins && 
          previousState.losses === currentState.losses && 
          previousState.rank === currentState.rank) {
              console.log("[INIT] Current URL parameters define a state identical to the previous stored state. This is likely a refresh. Setting previousState = currentState to prevent rank animation.");
              previousState = { ...currentState }; // Prevent rank animation on refresh if rank didn't change
          } else {
              console.log("[INIT] Current URL parameters differ from previous state. Rank animation will likely occur.");
          }
  }  
  console.log("INITIAL LOAD - Previous State:", previousState);
  console.log("INITIAL LOAD - Current State:", currentState);

  dom.wins.textContent = previousState.wins; // Set initial numbers to previous state for animation
  dom.losses.textContent = previousState.losses; // Set initial numbers to previous state for animation
  setGradientFill(dom.winsFillGradient, previousState.wins);
  setGradientFill(dom.lossesFillGradient, previousState.losses);
    const initialRankInfo = getRankInfo(currentState.rank); 
  dom.rankImage.src = initialRankInfo.img;
  dom.rankValue.textContent = initialRankInfo.display;
  showWidgetAndAnimateContent();
  localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(currentState));
  window.addEventListener('obsSourceCustomEvent', function(event) {
      if (event.detail.eventType === 'widget_state_update') {
          const data = event.detail.data;
          const newWins = data.wins;
          const newLosses = data.losses;
          const newAbsoluteRank = getAbsoluteRankIndex({ rankIndex: data.rankIndex, rankLevel: data.rankLevel });
          if (data.settings) {
              document.documentElement.style.setProperty('--bg-color', data.settings.bgColor);
              document.documentElement.style.setProperty('--wins-color', data.settings.winsColor);
              document.documentElement.style.setProperty('--losses-color', data.settings.lossesColor);
              document.documentElement.style.setProperty('--rank-text-color', data.settings.rankTextColor);
              document.documentElement.style.setProperty('--font', data.settings.font);
              document.documentElement.style.setProperty('--font-size', data.settings.fontSize);
              document.documentElement.style.setProperty('--animation-duration-in', `${data.settings.animDurationIn}s`);
              document.documentElement.style.setProperty('--animation-duration-out', `${data.settings.animDurationOut}s`);
              document.documentElement.style.setProperty('--animation-timing-function', data.settings.animationTimingFunction);
              dom.widget.style.background = data.settings.bgImage ? `url('${data.settings.bgImage}') center/cover no-repeat` : data.settings.bgColor;
          }

          const isRankChanged = (newAbsoluteRank !== currentState.rank);
          const isWinsChanged = (newWins !== currentState.wins);
          const isLossesChanged = (newLosses !== currentState.losses);

          console.log(`[OBS Event] Triggered. Data: rankIndex=${data.rankIndex}, rankLevel=${data.rankLevel} -> newAbsoluteRank=${newAbsoluteRank}`);
          console.log(`[OBS Event] Is Rank Changed? ${isRankChanged}, Wins Changed? ${isWinsChanged}, Losses Changed? ${isLossesChanged}`);
          console.log(`[OBS Event] Current State BEFORE update: Wins=${currentState.wins}, Losses=${currentState.losses}, Rank=${currentState.rank} (${getRankInfo(currentState.rank).display})`);
          previousState = { ...currentState }; 
          currentState = { 
              wins: newWins,
              losses: newLosses,
              rank: newAbsoluteRank
          };

          console.log(`[OBS Event] Previous State AFTER update: Wins=${previousState.wins}, Losses=${previousState.losses}, Rank=${previousState.rank} (${getRankInfo(previousState.rank).display})`);
          console.log(`[OBS Event] Current State AFTER update: Wins=${currentState.wins}, Losses=${currentState.losses}, Rank=${currentState.rank} (${getRankInfo(currentState.rank).display})`);

          localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(currentState));

          showWidgetAndAnimateContent();
      }
  });
});
import init from './just-life.js';

const canvas = document.getElementById('game-canvas');

function resizeCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
}

window.addEventListener('resize', resizeCanvas);
resizeCanvas();

init({
    canvas,
});
